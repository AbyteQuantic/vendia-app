import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/online_orders/online_orders_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Dashboard bell for pending web orders.
///
/// Polls GET /online-orders?status=pending every 15 s (brief's
/// cadence) and renders a red badge with the count when there is
/// at least one pedido waiting for a decision. Tapping opens the
/// dedicated KDS screen.
///
/// Polling is opt-in via the [enabled] flag so tests (and the
/// onboarding dashboard before a tenant has configured anything)
/// can mount the widget without burning network round-trips.
class OnlineOrdersBell extends StatefulWidget {
  const OnlineOrdersBell({
    super.key,
    this.enabled = true,
    this.pollInterval = const Duration(seconds: 15),
    this.size = 44,
    this.iconColor,
  });

  final bool enabled;
  final Duration pollInterval;
  final double size;
  final Color? iconColor;

  @override
  State<OnlineOrdersBell> createState() => _OnlineOrdersBellState();
}

class _OnlineOrdersBellState extends State<OnlineOrdersBell> {
  ApiService? _api;
  int _count = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(OnlineOrdersBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the screen toggles the bell off (e.g., logout), kill the
    // timer so we don't keep hitting the API with a stale token.
    if (oldWidget.enabled != widget.enabled) {
      _pollTimer?.cancel();
      if (widget.enabled) {
        _startPolling();
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    // Fire-and-forget the first fetch so initState stays synchronous
    // and ApiService (which reads dotenv) can fail gracefully in
    // widget tests without tearing down the tree.
    unawaited(_refresh());
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  ApiService? _ensureApi() {
    if (_api != null) return _api;
    try {
      _api = ApiService(AuthService());
    } catch (_) {
      // dotenv / keychain not initialised (typical in widget tests
      // without .env fixtures). Keep the bell visually static at
      // zero so the surrounding dashboard renders cleanly.
      return null;
    }
    return _api;
  }

  Future<void> _refresh() async {
    final api = _ensureApi();
    if (api == null) return;
    try {
      final list = await api.fetchOnlineOrders(status: 'pending');
      if (!mounted) return;
      setState(() => _count = list.length);
    } catch (_) {
      // Offline / 401 / 5xx: keep the last known count so the
      // badge doesn't flicker to 0 on a transient failure.
    }
  }

  void _open() {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const OnlineOrdersScreen()))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _count > 0
          ? 'Pedidos web pendientes: $_count'
          : 'Pedidos web, ninguno pendiente',
      child: GestureDetector(
        key: const Key('dashboard_orders_bell'),
        onTap: _open,
        child: SizedBox(
          width: widget.size + 8,
          height: widget.size + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: _count > 0
                        ? AppTheme.error.withValues(alpha: 0.08)
                        : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _count > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    color: _count > 0 ? AppTheme.error : (widget.iconColor ?? AppTheme.textSecondary),
                    size: 24,
                  ),
                ),
              ),
              if (_count > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    key: const Key('dashboard_orders_badge'),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _count > 99 ? '99+' : '$_count',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
