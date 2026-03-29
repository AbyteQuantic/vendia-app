import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../models/order_ticket.dart';
import '../../utils/format_cop.dart';

/// KdsFastfoodScreen — Kitchen Display for fast-food / prepaid context.
/// No "Cobrar" button (customer already paid). Only "Pedido Listo para Entregar".
class KdsFastfoodScreen extends StatefulWidget {
  const KdsFastfoodScreen({super.key});

  @override
  State<KdsFastfoodScreen> createState() => _KdsFastfoodScreenState();
}

class _KdsFastfoodScreenState extends State<KdsFastfoodScreen> {
  // ── Mock orders ──
  late List<_FastFoodOrder> _orders;

  @override
  void initState() {
    super.initState();
    _orders = [
      _FastFoodOrder(
        label: 'Turno 15',
        customerName: 'Juan',
        isParaLlevar: true,
        status: _FFStatus.cooking,
        items: [
          OrderItem(
            productUuid: '1',
            productName: 'Hamburguesa',
            quantity: 2,
            unitPrice: 12000,
            emoji: '\ud83c\udf54',
          ),
          OrderItem(
            productUuid: '2',
            productName: 'Perro Caliente',
            quantity: 1,
            unitPrice: 5000,
            emoji: '\ud83c\udf2d',
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      _FastFoodOrder(
        label: 'Turno 16',
        customerName: 'Mar\u00eda',
        isParaLlevar: false,
        status: _FFStatus.cooking,
        items: [
          OrderItem(
            productUuid: '3',
            productName: 'Bandeja Paisa',
            quantity: 1,
            unitPrice: 18000,
            emoji: '\ud83c\udf5b',
          ),
          OrderItem(
            productUuid: '4',
            productName: 'Jugo Natural',
            quantity: 2,
            unitPrice: 4000,
            emoji: '\ud83e\uddc3',
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
      _FastFoodOrder(
        label: 'Turno 17',
        customerName: 'Pedro',
        isParaLlevar: true,
        status: _FFStatus.cooking,
        items: [
          OrderItem(
            productUuid: '5',
            productName: 'Empanada',
            quantity: 4,
            unitPrice: 2000,
            emoji: '\ud83e\udd5f',
          ),
          OrderItem(
            productUuid: '6',
            productName: 'Gaseosa',
            quantity: 2,
            unitPrice: 2500,
            emoji: '\ud83e\udd64',
          ),
        ],
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      ),
    ];
  }

  int get _newCount =>
      _orders.where((o) => o.status == _FFStatus.cooking).length;

  void _markReady(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _orders[index] = _orders[index].copyWith(status: _FFStatus.ready);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_orders[index].label} listo para entregar',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
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
              'Pedidos en Cocina',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            if (_newCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$_newCount nuevos',
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
                'No hay pedidos en cocina',
                style: TextStyle(fontSize: 20, color: AppTheme.textSecondary),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (_, i) => _FastFoodOrderCard(
                order: _orders[i],
                timeAgo: _timeAgo(_orders[i].createdAt),
                onReady: () => _markReady(i),
              ),
            ),
    );
  }
}

// ── Fast-food order card ───────────────────────────────────────────────────────

class _FastFoodOrderCard extends StatelessWidget {
  final _FastFoodOrder order;
  final String timeAgo;
  final VoidCallback onReady;

  const _FastFoodOrderCard({
    required this.order,
    required this.timeAgo,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final total =
        order.items.fold<double>(0, (sum, item) => sum + item.subtotal);
    final isReady = order.status == _FFStatus.ready;

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
              Text(
                order.label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isReady ? AppTheme.success : AppTheme.error,
                ),
              ),
              const SizedBox(width: 10),
              if (order.isParaLlevar)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B),
                      width: 1.5,
                    ),
                  ),
                  child: const Text(
                    'Para llevar',
                    style: TextStyle(
                      fontSize: 16, // badge (exempt: compact)
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ),
              if (isReady) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              const Spacer(),
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

          const SizedBox(height: 8),

          // ── Customer name ──
          Text(
            'Cliente: ${order.customerName}',
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
                  Text(
                    formatCOP(item.subtotal),
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ── Total ──
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: ${formatCOP(total)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Action button: only "Listo para Entregar" (no cobrar in prepaid) ──
          if (!isReady)
            Semantics(
              button: true,
              label: 'Marcar pedido listo para entregar',
              child: GestureDetector(
                onTap: onReady,
                child: Container(
                  width: double.infinity,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '\u2705 Pedido Listo para Entregar',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else
            // Already ready — show completed state
            Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.success, width: 2),
              ),
              alignment: Alignment.center,
              child: const Text(
                '\u2705 Entregado',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Local models ───────────────────────────────────────────────────────────────

enum _FFStatus { cooking, ready }

class _FastFoodOrder {
  final String label;
  final String customerName;
  final bool isParaLlevar;
  final _FFStatus status;
  final List<OrderItem> items;
  final DateTime createdAt;

  const _FastFoodOrder({
    required this.label,
    required this.customerName,
    required this.isParaLlevar,
    required this.status,
    required this.items,
    required this.createdAt,
  });

  _FastFoodOrder copyWith({_FFStatus? status}) {
    return _FastFoodOrder(
      label: label,
      customerName: customerName,
      isParaLlevar: isParaLlevar,
      status: status ?? this.status,
      items: items,
      createdAt: createdAt,
    );
  }
}
