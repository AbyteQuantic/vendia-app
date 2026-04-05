import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../database_service.dart';
import '../collections/pending_operation.dart';
import '../collections/local_product.dart';
import 'connectivity_monitor.dart';

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

      final response = await _dio.get(
        '/api/v1/products',
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
