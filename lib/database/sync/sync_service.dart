import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../database_service.dart';
import '../collections/pending_operation.dart';
import '../collections/local_payment_method.dart';
import '../collections/local_product.dart';
import 'connectivity_monitor.dart';
import 'sales_sync.dart';

enum SyncStatus { synced, syncing, offline, error }

class SyncService extends ChangeNotifier {
  final DatabaseService _db;
  final ConnectivityMonitor _connectivity;
  final AuthService _auth;
  late final Dio _dio;

  Timer? _timer;
  SyncStatus _status = SyncStatus.synced;
  int _pendingCount = 0;

  SyncStatus get status => _status;
  int get pendingCount => _pendingCount;

  SyncService({
    required DatabaseService db,
    required ConnectivityMonitor connectivity,
    required AuthService auth,
  })  : _db = db,
        _connectivity = connectivity,
        _auth = auth {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  Future<void> startBackgroundSync() async {
    _connectivity.addListener(_onConnectivityChange);
    await _refreshPendingCount();
    _updateStatusFromState();

    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isOnline) syncNow();
    });

    if (_connectivity.isOnline) {
      await syncNow();
    }
  }

  void _onConnectivityChange() {
    if (_connectivity.isOnline) {
      syncNow();
    } else {
      _status = SyncStatus.offline;
      notifyListeners();
    }
  }

  Future<void> syncNow() async {
    if (!_connectivity.isOnline) {
      _status = SyncStatus.offline;
      notifyListeners();
      return;
    }

    // Spec 047: las ventas offline suben por POST /api/v1/sales (idempotente
    // por UUID), NO por /sync/batch — esa ruta para 'sale' estaba rota y
    // envenenaba el lote. pushToServer() drena cada LocalSale(synced=false).
    // Va aquí, en syncNow(), para que el timer de 30 s y la reconexión
    // (_onConnectivityChange) cubran las ventas: antes solo se empujaban al
    // arrancar la app, así que una venta hecha con la app ABIERTA nunca
    // sincronizaba hasta reiniciar. pushToServer ya traga sus errores por venta.
    await SalesSyncService.pushToServer();

    await _refreshPendingCount();
    if (_pendingCount == 0) {
      await _pullFromServer();
      _status = SyncStatus.synced;
      notifyListeners();
      return;
    }

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      final ops = await _db.getPendingOps(limit: 50);
      if (ops.isEmpty) {
        _status = SyncStatus.synced;
        notifyListeners();
        return;
      }

      final token = await _auth.getToken();
      final payload = ops.map((op) => op.toSyncPayload()).toList();

      final response = await _dio.post(
        '/api/v1/sync/batch',
        data: {'operations': payload},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final successIds = <int>[];
      final responseData = response.data as Map<String, dynamic>?;

      if (responseData != null) {
        // Apply server changes if any
        final serverChanges = responseData['server_changes'] as List?;
        if (serverChanges != null) {
          await _applyServerChanges(serverChanges);
        }
      }

      // Mark all sent ops as successful
      successIds.addAll(ops.map((op) => op.id));
      await _db.removePendingOps(successIds);

      await _refreshPendingCount();
      _status = _pendingCount > 0 ? SyncStatus.error : SyncStatus.synced;
    } on DioException catch (_) {
      for (final op in await _db.getPendingOps(limit: 50)) {
        if (op.retryCount > 10) continue;
        await _db.incrementRetryCount(op.id);
      }
      _status = SyncStatus.error;
    } catch (_) {
      _status = SyncStatus.error;
    }

    notifyListeners();
  }

  Future<void> enqueue(PendingOperation op) async {
    // H10 fix: stamp the active tenant on every queued op so a
    // workspace switch can't orphan / leak the work. Callers don't
    // have to remember to set it — the sync service is the choke
    // point. If the cashier has no tenant yet (rare bootstrap
    // race), the empty string is preserved so the op is still
    // accepted; the sync engine treats `''` as legacy and skips
    // filtering — server-side validation rejects mismatched
    // tenants anyway.
    if (op.tenantId.isEmpty) {
      op.tenantId = (await _auth.getTenantId()) ?? '';
    }
    await _db.addPendingOp(op);
    await _refreshPendingCount();
    _updateStatusFromState();
    notifyListeners();

    if (_connectivity.isOnline) {
      syncNow();
    }
  }

  Future<void> _pullFromServer() async {
    try {
      final token = await _auth.getToken();
      if (token == null) return;

      // Spec 014: the POS reads products from Isar, populated here.
      // Inventario and Dashboard fetch with `?branch_id=` via
      // ApiService.fetchProducts. This pull must use the SAME sede
      // scope so all three screens see one consistent set — otherwise
      // the POS shows products the other screens never load.
      final params = <String, dynamic>{
        // Caché Isar = fuente del POS: NO guardar platos de menú incompletos
        // (sin receta con ingredientes). Así no aparecen en ventas y, al leer
        // de Isar, el filtro se mantiene aun offline. Spec 078.
        'sellable_only': 'true',
      };
      final branchId = ApiService.currentBranchId;
      if (branchId != null && branchId.isNotEmpty) {
        params['branch_id'] = branchId;
      }

      final response = await _dio.get(
        '/api/v1/products',
        queryParameters: params,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final list = (response.data['data'] as List?) ?? [];
      final products = list
          .map((e) => LocalProduct.fromJson(e as Map<String, dynamic>))
          .toList();
      // Replace all local products with server data (removes deleted ones)
      await _db.replaceAllProducts(products);
    } catch (_) {
      // Silent fail on pull — local data still works
    }

    // Pull tenant payment methods so the checkout can render the
    // owner-configured set (e.g. Nequi, Daviplata) for cashiers as
    // well. Tenant scope is already enforced by the endpoint.
    try {
      final token = await _auth.getToken();
      if (token == null) return;

      final pmResponse = await _dio.get(
        '/api/v1/store/payment-methods',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final pmList = (pmResponse.data['data'] as List?) ?? [];
      final methods = pmList
          .map((e) =>
              LocalPaymentMethod.fromJson(e as Map<String, dynamic>))
          .toList();
      await _db.replaceAllPaymentMethods(methods);
    } catch (_) {
      // Silent: leave the previous cache in place
    }

    // Spec 053 — PULL de mesas abiertas: un dispositivo nuevo / reconectado
    // no conoce los labels, así que GET /tables/open las "trae" y se fusionan
    // en Isar con LWW por mesa (planOpenTabsMerge). El push de mesas ya ocurre
    // inline en commitOrderToTab→upsertTableTab; esto cierra el lado de lectura
    // para que las cuentas abiertas sean visibles en cualquier equipo.
    try {
      final token = await _auth.getToken();
      if (token == null) return;
      final tabsResp = await _dio.get(
        '/api/v1/tables/open',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final tabsList = ((tabsResp.data['data'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      await _db.applyServerOpenTabs(tabsList);
    } catch (_) {
      // Silent: las mesas locales siguen funcionando sin el pull.
    }
  }

  Future<void> _applyServerChanges(List<dynamic> changes) async {
    for (final change in changes) {
      final map = change as Map<String, dynamic>;
      final entity = map['entity'] as String?;
      final data = map['data'] as Map<String, dynamic>?;
      if (entity == null || data == null) continue;

      switch (entity) {
        case 'product':
          await _db.upsertProduct(LocalProduct.fromJson(data));
        case 'customer':
          // Future: handle customer sync
          break;
      }
    }
  }

  Future<void> _refreshPendingCount() async {
    _pendingCount = await _db.getPendingCount();
  }

  void _updateStatusFromState() {
    if (!_connectivity.isOnline) {
      _status = SyncStatus.offline;
    } else if (_pendingCount > 0) {
      _status = SyncStatus.error;
    } else {
      _status = SyncStatus.synced;
    }
  }

  void stop() {
    _timer?.cancel();
    _connectivity.removeListener(_onConnectivityChange);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
