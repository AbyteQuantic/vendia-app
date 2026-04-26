import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// KDS (Kitchen Display System) — Phase 1.
///
/// Lists the pedidos web that are still pending (`status = 'pending'`)
/// plus the most recent decisions so the tendero can walk back a
/// mistap. Poll cadence matches the dashboard bell (15 s) so the
/// tendero never has to pull-to-refresh.
///
/// State vocab is lowercase-English on the wire — "NUEVO / ACEPTADO"
/// Spanish labels in the brief are UI translations only. The backend
/// whitelists `pending/accepted/rejected/completed` on PATCH so a
/// typo here 400s instead of wedging the row.
class OnlineOrdersScreen extends StatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  ApiService? _api;
  List<dynamic> _orders = const [];
  bool _loading = true;
  String? _errorMessage;
  // Tracks which order row is in the middle of a PATCH so the
  // buttons can flip to a spinner without blocking other rows.
  final Set<String> _mutating = {};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Defer ApiService construction until we actually need it so
    // widget tests without dotenv fixtures don't crash during
    // initState (see OnlineOrdersBell for the same pattern).
    unawaited(_load(initial: true));
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _load(),
    );
  }

  ApiService? _ensureApi() {
    if (_api != null) return _api;
    try {
      _api = ApiService(AuthService());
    } catch (_) {
      return null;
    }
    return _api;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    final api = _ensureApi();
    if (api == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (initial) _errorMessage = 'No pudimos inicializar la conexión.';
      });
      return;
    }
    try {
      // Both pending AND accepted live here so the staff has a
      // single surface for the whole life cycle: pending rows show
      // Aceptar/Rechazar, accepted rows show "Marcar entregado".
      // The customer-side portal polls /my-orders and reflects the
      // status flips in its 3-step timeline (Recibido / Preparando
      // / En camino).
      final pendingFuture = api.fetchOnlineOrders(status: 'pending');
      final acceptedFuture = api.fetchOnlineOrders(status: 'accepted');
      final results = await Future.wait([pendingFuture, acceptedFuture]);
      final combined = <dynamic>[...results[0], ...results[1]];
      // Sort newest first so a fresh "pending" lands on top.
      combined.sort((a, b) {
        final ac = ((a as Map)['created_at'] as String?) ?? '';
        final bc = ((b as Map)['created_at'] as String?) ?? '';
        return bc.compareTo(ac);
      });
      if (!mounted) return;
      setState(() {
        _orders = combined;
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (initial) {
          _errorMessage = 'No pudimos cargar los pedidos: $e';
        }
      });
    }
  }

  Future<void> _decide(String id, String status, String confirmation) async {
    HapticFeedback.mediumImpact();
    setState(() => _mutating.add(id));
    final api = _ensureApi();
    if (api == null) {
      if (mounted) setState(() => _mutating.remove(id));
      return;
    }
    try {
      await api.updateOnlineOrderStatus(id, status);
      if (!mounted) return;
      // Remove locally so the list responds instantly — the next
      // poll reconciles with the server.
      setState(() {
        _orders = _orders
            .where((o) => (o as Map)['id'] != id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(confirmation),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _mutating.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Pedidos Web',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.textPrimary),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _orders.isEmpty) {
      return _EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Sin conexión',
        subtitle: _errorMessage!,
        action: TextButton(
          onPressed: () => _load(initial: true),
          child: const Text('Reintentar'),
        ),
      );
    }
    if (_orders.isEmpty) {
      return const _EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Sin pedidos pendientes',
        subtitle:
            'Cuando un cliente haga un pedido desde tu catálogo, aparecerá aquí al instante.',
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (ctx, i) {
          final order = _orders[i] as Map<String, dynamic>;
          return _OrderCard(
            order: order,
            busy: _mutating.contains(order['id'] as String),
            onAccept: () => _decide(
                order['id'] as String, 'accepted', 'Pedido aceptado'),
            onReject: () => _decide(
                order['id'] as String, 'rejected', 'Pedido rechazado'),
            onComplete: () => _decide(
                order['id'] as String, 'completed', 'Pedido entregado'),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: _orders.length,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onComplete,
  });

  final Map<String, dynamic> order;
  final bool busy;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;
  final Future<void> Function() onComplete;

  String _formatCOP(num amount) {
    final v = amount.round();
    final s = v.abs().toString();
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  /// items is stored as a JSON-encoded string on the wire
  /// (`[{name, quantity, price}]`). A malformed payload just falls
  /// back to an empty list so the card still renders headline info.
  List<String> _formatItems() {
    final raw = order['items'];
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => '${m['quantity'] ?? 1}x ${m['name'] ?? 'item'}')
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] as String?) ?? 'pending';
    final total = (order['total_amount'] as num?) ?? 0;
    final name = (order['customer_name'] as String?) ?? '—';
    final phone = (order['customer_phone'] as String?) ?? '';
    final delivery = (order['delivery_type'] as String?) ?? 'pickup';
    final method = (order['payment_method'] as String?) ?? '';
    final items = _formatItems();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (status == 'accepted')
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'PREPARANDO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                _formatCOP(total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              delivery == 'delivery' ? 'Domicilio' : 'Recoge en tienda',
              if (method.isNotEmpty) method,
              if (phone.isNotEmpty) phone,
            ].join(' · '),
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final line in items)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $line',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textPrimary),
                ),
              ),
          ],
          const SizedBox(height: 14),
          // Action row varies by state. The customer-side timeline
          // shows: Recibido (pending) -> Preparando (accepted) ->
          // En camino (completed). The mapping here mirrors that
          // so the staff thinks in the same vocabulary.
          //
          // SizedBox(double.infinity) forces the button to span the
          // card's content width; without it FilledButton.icon
          // shrink-wraps to its label and the rounded corners
          // collide with the card on small phones.
          if (status == 'accepted')
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('order_complete_${order['id']}'),
                onPressed: busy ? null : onComplete,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.local_shipping_rounded),
                label: const Text(
                  'Marcar entregado',
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.primary,
                  // explicit shape stops the rounded corners from
                  // bleeding past the card border in any dpr.
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('order_reject_${order['id']}'),
                    onPressed: busy ? null : onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Rechazar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: AppTheme.error,
                      side: BorderSide(
                          color: AppTheme.error.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: Key('order_accept_${order['id']}'),
                    onPressed: busy ? null : onAccept,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Aceptar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppTheme.success,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondary,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
