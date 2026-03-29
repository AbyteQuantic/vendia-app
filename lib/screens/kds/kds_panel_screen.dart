import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../models/order_ticket.dart';
import '../../utils/format_cop.dart';

/// KdsPanelScreen — Kitchen Display for bar/restaurant context.
/// Shows pending orders with "Listo" and "Cobrar" actions.
class KdsPanelScreen extends StatefulWidget {
  const KdsPanelScreen({super.key});

  @override
  State<KdsPanelScreen> createState() => _KdsPanelScreenState();
}

class _KdsPanelScreenState extends State<KdsPanelScreen> {
  // ── Mock orders ──
  late List<_KdsOrder> _orders;

  @override
  void initState() {
    super.initState();
    _orders = [
      _KdsOrder(
        label: 'Mesa 4',
        waiterName: 'Carlos',
        status: _KdsStatus.pending,
        items: [
          OrderItem(
            productUuid: '1',
            productName: 'Cerveza \u00c1guila',
            quantity: 3,
            unitPrice: 3500,
            emoji: '\ud83c\udf7a',
          ),
          OrderItem(
            productUuid: '2',
            productName: 'Empanada',
            quantity: 1,
            unitPrice: 2000,
            emoji: '\ud83e\udd5f',
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      _KdsOrder(
        label: 'Turno 7',
        waiterName: 'Ana',
        status: _KdsStatus.ready,
        items: [
          OrderItem(
            productUuid: '3',
            productName: 'Gaseosa',
            quantity: 2,
            unitPrice: 2500,
            emoji: '\ud83e\udd64',
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ];
  }

  int get _pendingCount =>
      _orders.where((o) => o.status == _KdsStatus.pending).length;

  void _markReady(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _orders[index] = _orders[index].copyWith(status: _KdsStatus.ready);
    });
  }

  void _markCobrar(int index) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cobrando ${_orders[index].label}...',
          style: const TextStyle(fontSize: 18),
        ),
        backgroundColor: AppTheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _timeAgo(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    return 'Hace ${diff.inHours}h ${diff.inMinutes % 60}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Row(
          children: [
            const Text(
              'Pedidos en Espera',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            if (_pendingCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$_pendingCount pedidos nuevos',
                  style: const TextStyle(
                    fontSize: 16, // badge text (exempt: compact badge)
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: _orders.isEmpty
          ? const Center(
              child: Text(
                'No hay pedidos pendientes',
                style: TextStyle(fontSize: 20, color: AppTheme.textSecondary),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (_, i) => _KdsOrderCard(
                order: _orders[i],
                timeAgo: _timeAgo(_orders[i].createdAt),
                onReady: () => _markReady(i),
                onCobrar: () => _markCobrar(i),
              ),
            ),
    );
  }
}

// ── Order card widget ──────────────────────────────────────────────────────────

class _KdsOrderCard extends StatelessWidget {
  final _KdsOrder order;
  final String timeAgo;
  final VoidCallback onReady;
  final VoidCallback onCobrar;

  const _KdsOrderCard({
    required this.order,
    required this.timeAgo,
    required this.onReady,
    required this.onCobrar,
  });

  @override
  Widget build(BuildContext context) {
    final total = order.items.fold<double>(
        0, (sum, item) => sum + item.subtotal);
    final isReady = order.status == _KdsStatus.ready;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isReady ? AppTheme.success : AppTheme.borderColor,
          width: isReady ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      order.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (isReady) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '\u2705 Listo',
                          style: TextStyle(
                            fontSize: 16, // badge (exempt: compact)
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                timeAgo,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ── Waiter name ──
          Text(
            'Mesero: ${order.waiterName}',
            style: const TextStyle(
              fontSize: 18,
              color: AppTheme.textSecondary,
            ),
          ),

          const SizedBox(height: 12),

          // ── Items list ──
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    item.emoji ?? '\ud83d\udce6',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${item.productName} \u00d7 ${item.quantity}',
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // ── Total ──
          Text(
            'Total: ${formatCOP(total)}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 16),

          // ── Action buttons ──
          if (isReady)
            // Ready state: single "Cobrar" button
            Semantics(
              button: true,
              label: 'Cobrar ${formatCOP(total)}',
              child: GestureDetector(
                onTap: onCobrar,
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Cobrar ${formatCOP(total)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else
            // Pending state: "Listo" + "Cobrar" side by side
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Marcar como listo',
                    child: GestureDetector(
                      onTap: onReady,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '\u2705 Listo',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Cobrar pedido',
                    child: GestureDetector(
                      onTap: onCobrar,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '\ud83d\udcb0 Cobrar',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
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

// ── Local models ───────────────────────────────────────────────────────────────

enum _KdsStatus { pending, ready }

class _KdsOrder {
  final String label;
  final String waiterName;
  final _KdsStatus status;
  final List<OrderItem> items;
  final DateTime createdAt;

  const _KdsOrder({
    required this.label,
    required this.waiterName,
    required this.status,
    required this.items,
    required this.createdAt,
  });

  _KdsOrder copyWith({_KdsStatus? status}) {
    return _KdsOrder(
      label: label,
      waiterName: waiterName,
      status: status ?? this.status,
      items: items,
      createdAt: createdAt,
    );
  }
}
