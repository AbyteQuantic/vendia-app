import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'app_error.dart';

/// View of who currently holds a single POS cart slot.
class CartSessionInfo {
  final int cartIndex;
  final String userId;
  final String employeeName;
  final String role;
  final DateTime startedAt;
  final DateTime lastHeartbeat;

  const CartSessionInfo({
    required this.cartIndex,
    required this.userId,
    required this.employeeName,
    required this.role,
    required this.startedAt,
    required this.lastHeartbeat,
  });

  factory CartSessionInfo.fromJson(Map<String, dynamic> j) => CartSessionInfo(
        cartIndex: (j['cart_index'] as num?)?.toInt() ?? 0,
        userId: (j['user_id'] ?? '') as String,
        employeeName: (j['employee_name'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        startedAt: DateTime.tryParse(j['started_at']?.toString() ?? '') ??
            DateTime.now(),
        lastHeartbeat:
            DateTime.tryParse(j['last_heartbeat']?.toString() ?? '') ??
                DateTime.now(),
      );

  /// Friendly label for the lock badge — falls back to the role
  /// (Cajero / Mesero) when the employee_name claim is empty, which
  /// happens for legacy tokens that don't carry the user's name.
  String get displayLabel {
    if (employeeName.isNotEmpty) return employeeName;
    switch (role) {
      case 'owner':
        return 'Propietario';
      case 'admin':
        return 'Administrador';
      case 'cashier':
        return 'Cajero';
      case 'waiter':
        return 'Mesero';
      default:
        return 'Otro usuario';
    }
  }
}

/// Coordinates the live cart-lock state with the backend so two
/// devices never edit the same cuenta simultaneously.
///
/// Behavior:
///   - On `bindToCart(idx)`: claims the slot and starts a 30s
///     heartbeat. If the slot is held by another user, exposes the
///     conflict via the `lastConflict` notifier (UI shows a snackbar).
///   - Polls the global snapshot every 10s so badges on OTHER tabs
///     update without user input. Pauses when the app is in the
///     background (caller hooks WidgetsBindingObserver).
///   - `release()` drops the held slot and clears local state.
///
/// Robust to backend errors: network failures don't crash the POS,
/// they just leave `sessions` as the last-known snapshot. The cashier
/// can keep selling offline; on reconnect the service catches up.
class CartSessionService extends ChangeNotifier {
  CartSessionService(this._api);

  final ApiService _api;

  Map<int, CartSessionInfo> _sessions = const {};
  Map<int, CartSessionInfo> get sessions => _sessions;

  int? _heldIndex;
  int? get heldIndex => _heldIndex;

  CartSessionInfo? _lastConflict;
  CartSessionInfo? get lastConflict => _lastConflict;

  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Fetches the current snapshot. Call once when the POS mounts so
  /// the tab badges paint immediately, then again on each poll tick.
  Future<void> refreshSnapshot() async {
    try {
      final list = await _api.listCartSessions();
      if (_disposed) return;
      _sessions = {
        for (final s in list) s.cartIndex: s,
      };
      notifyListeners();
    } catch (_) {
      // Offline — keep stale snapshot. UI shouldn't blank out the
      // existing badges just because the network blipped.
    }
  }

  /// Begins watching cart slots — single 10-second poll loop.
  void startPolling() {
    _pollTimer?.cancel();
    refreshSnapshot();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refreshSnapshot(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Claim the given slot for the current user. Returns true on
  /// success, false on conflict (lastConflict populated).
  Future<bool> bindToCart(int cartIndex) async {
    try {
      final mine = await _api.claimCartSession(cartIndex);
      if (_disposed) return false;
      _heldIndex = cartIndex;
      _lastConflict = null;
      // Update local snapshot eagerly so the lock badge moves before
      // the next poll lands.
      _sessions = {..._sessions, cartIndex: mine};
      _startHeartbeat();
      notifyListeners();
      return true;
    } on AppError catch (e) {
      if (_disposed) return false;
      if (e.statusCode == 409 && e.payload != null) {
        final holder = e.payload?['holder'];
        if (holder is Map<String, dynamic>) {
          _lastConflict =
              CartSessionInfo.fromJson(holder.cast<String, dynamic>());
          _sessions = {..._sessions, cartIndex: _lastConflict!};
          notifyListeners();
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Release the currently-held slot (if any) and stop heartbeating.
  Future<void> release() async {
    final idx = _heldIndex;
    _heldIndex = null;
    _stopHeartbeat();
    if (idx == null) return;
    try {
      await _api.releaseCartSession(idx);
    } catch (_) {
      // Best-effort. The 5-min stale-prune on the backend will free
      // it eventually if we couldn't reach the network.
    }
    if (_disposed) return;
    final next = {..._sessions}..remove(idx);
    _sessions = next;
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        final idx = _heldIndex;
        if (idx == null) return;
        try {
          await _api.heartbeatCartSession(idx);
        } catch (_) {
          // Another offline gap — heartbeat resumes when network is
          // back. The 5-min staleness window is intentionally long
          // enough to absorb a typical cellular hiccup.
        }
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopHeartbeat();
    stopPolling();
    super.dispose();
  }
}
