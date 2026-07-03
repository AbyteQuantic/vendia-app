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

/// Tope de reintentos para un op de la cola genérica de /sync/batch antes de
/// descartarlo. Igual al umbral que ya existía (retryCount > 10) pero ahora
/// el op se DESCARTA al llegar al tope en vez de quedar congelado
/// re-enviándose (y re-envenenando el lote) para siempre.
const int maxSyncOpRetries = 10;

/// True cuando una operación de la cola genérica debe DESCARTARSE en vez de
/// reintentarse. Ver el comentario en syncNow() sobre por qué la señal es
/// retryCount y no un status code (a diferencia de
/// `isPermanentSalePushError` en sales_sync.dart, que sí puede confiar en
/// 400/422 porque /sales es un endpoint dedicado por venta).
@visibleForTesting
bool shouldDropSyncOp(int retryCount) => retryCount >= maxSyncOpRetries;

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

  @visibleForTesting
  set httpClientAdapterForTesting(HttpClientAdapter adapter) =>
      _dio.httpClientAdapter = adapter;

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

      // Cada operación va en su PROPIO POST /sync/batch (lote de 1), no
      // todas juntas en un solo request. El backend envuelve el lote
      // completo en una transacción (sync_service.go ProcessBatch): un
      // único op con payload inválido hace fallar la transacción entera, y
      // el código viejo dejaba TODOS los ops de ese lote (hasta 50) sin
      // sincronizar para siempre porque el op envenenado nunca se quitaba
      // de getPendingOps() — el bug histórico del "lote envenenado" (Spec
      // 047, arreglado para ventas vía /sales) reproducido aquí para
      // fiado/crédito (entity credit_account/credit_payment), que siguen
      // yendo por /sync/batch. Mandando uno por uno, un op malo nunca
      // bloquea a sus hermanos de cola.
      for (final op in ops) {
        try {
          final response = await _dio.post(
            '/api/v1/sync/batch',
            data: {'operations': [op.toSyncPayload()]},
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );

          final responseData = response.data as Map<String, dynamic>?;
          final serverChanges = responseData?['server_changes'] as List?;
          if (serverChanges != null) {
            await _applyServerChanges(serverChanges);
          }

          await _db.removePendingOps([op.id]);
        } catch (e) {
          // El backend no distingue error permanente (payload inválido) de
          // transitorio (red caída, hiccup de BD) con un status code propio
          // para un op suelto — todo error de processOperation vuelve como
          // 500 genérico. Por eso la señal es retryCount: tras
          // maxSyncOpRetries intentos se asume payload permanentemente
          // inválido y se descarta (log fuerte) en vez de dejarlo congelado
          // re-envenenando cada sync para siempre.
          if (shouldDropSyncOp(op.retryCount)) {
            debugPrint('[SYNC] ⚠️ Operación descartada tras '
                '$maxSyncOpRetries intentos '
                '(${op.entity}/${op.action} ${op.uuid}): $e');
            await _db.removePendingOps([op.id]);
          } else {
            await _db.incrementRetryCount(op.id);
            debugPrint('[SYNC] Push transitorio falló para ${op.entity} '
                '${op.uuid} (reintentará): $e');
          }
          // Sigue con el siguiente op — uno malo no bloquea a los demás.
        }
      }

      await _refreshPendingCount();
      _status = _pendingCount > 0 ? SyncStatus.error : SyncStatus.synced;
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

  /// Trae TODAS las páginas de `/api/v1/products` (no solo la primera) para
  /// alimentar la caché Isar que usa el POS offline. Devuelve `null` si no
  /// hay token (nada que sincronizar aún).
  ///
  /// Auditoría 2026-07-02: esta llamada corre cada 30s (`Timer.periodic`) y
  /// antes hacía UNA sola petición sin `page`/`per_page` — el backend cae a
  /// su default `per_page=20` (`pagination.go`) y `replaceAllProducts`
  /// REEMPLAZA toda la caché Isar por esos 20 productos. En un tenant con
  /// más de 20 SKU esto truncaba silenciosamente el catálogo offline del
  /// POS cada medio minuto, en móvil real (Art. II). Mismo patrón de
  /// paginación completa que Spec 088 ya aplicó en cart_controller.dart —
  /// tope de seguridad 50 páginas (5000 productos).
  ///
  /// Extraído como método público (`@visibleForTesting`) porque la
  /// escritura a Isar (`_db.replaceAllProducts`) no es testeable sin un
  /// Isar real inicializado (ver `integration_test/isar_persistence_test.dart`)
  /// — este método sí lo es, con un `HttpClientAdapter` de prueba.
  @visibleForTesting
  Future<List<LocalProduct>?> fetchAllProductPagesForSync() async {
    final token = await _auth.getToken();
    if (token == null) return null;

    // Spec 014: el POS lee productos de Isar, poblada aquí. Inventario y
    // Dashboard hacen fetch con `?branch_id=` vía ApiService.fetchProducts.
    // Este pull debe usar el MISMO scope de sede para que las tres
    // pantallas vean el mismo set — de lo contrario el POS muestra
    // productos que las otras nunca cargan.
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

    final products = <LocalProduct>[];
    var page = 1;
    var totalPages = 1;
    do {
      final response = await _dio.get(
        '/api/v1/products',
        queryParameters: {...params, 'page': page, 'per_page': 100},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final list = (response.data['data'] as List?) ?? [];
      products.addAll(
          list.map((e) => LocalProduct.fromJson(e as Map<String, dynamic>)));
      totalPages = (response.data['total_pages'] as num?)?.toInt() ?? 1;
      page++;
    } while (page <= totalPages && page <= 50);
    return products;
  }

  Future<void> _pullFromServer() async {
    try {
      final products = await fetchAllProductPagesForSync();
      if (products == null) return; // sin token — nada que sincronizar aún
      // Replace all local products with server data (removes deleted ones)
      await _db.replaceAllProducts(products);
    } catch (e) {
      // Silent fail on pull — local data still works
      debugPrint(
          '[SYNC] Pull de productos falló, se mantiene el caché local: $e');
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
    } catch (e) {
      // Silent: leave the previous cache in place
      debugPrint(
          '[SYNC] Pull de métodos de pago falló, se mantiene el caché previo: $e');
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
    } catch (e) {
      // Silent: las mesas locales siguen funcionando sin el pull.
      debugPrint(
          '[SYNC] Pull de mesas abiertas falló, se mantienen las mesas locales: $e');
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
