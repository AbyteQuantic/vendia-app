// Spec: specs/107-dashboard-v2-resumen/spec.md
//
// Piezas visuales del inicio v2: remate oblicuo del héroe (CustomPaint),
// tarjetas con datos vivos (FR-05/06) y movimientos del día (FR-07).
// Diseño congelado: prototipo 626829d3 (paleta VendIA, íconos de trazo).
import 'package:flutter/material.dart';

import '../../services/home_summary_service.dart';
import '../../theme/app_theme.dart';

/// Remate oblicuo del héroe con chevron (forma "Cashly" aprobada).
class HeroTail extends StatelessWidget {
  const HeroTail({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 56,
      child: CustomPaint(painter: _TailPainter()),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * .06)
      ..quadraticBezierTo(w * .995, h * .42, w * .895, h * .52)
      ..lineTo(w * .595, h * .80)
      ..quadraticBezierTo(w * .5, h * 1.06, w * .405, h * .80)
      ..lineTo(w * .105, h * .52)
      ..quadraticBezierTo(w * .005, h * .42, 0, h * .06)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1173AD), Color(0xFF2E97D4), Color(0xFF3FB2DE)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, paint);

    final chevron = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cp = Path()
      ..moveTo(w * .5 - 11, h * .62)
      ..lineTo(w * .5, h * .76)
      ..lineTo(w * .5 + 11, h * .62);
    canvas.drawPath(cp, chevron);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Una tarjeta viva del bloque "Su negocio hoy".
class LiveCardData {
  const LiveCardData({
    required this.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  final String key;
  final IconData icon;
  final Color tint;
  final String title;
  final String value;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;
}

/// Construye las tarjetas según el resumen y las capacidades del tenant
/// (FR-05/06): solo las que aplican; estados vacíos amables (spec §9).
List<LiveCardData> buildLiveCards({
  required HomeSummary s,
  required bool hasOperation, // mesas/comandas/domicilios activos
  required VoidCallback onFiados,
  required VoidCallback onGanancias,
  required VoidCallback onOperacion,
  required VoidCallback onInventario,
  required VoidCallback onHistorial,
}) {
  final cards = <LiveCardData>[
    LiveCardData(
      key: 'receivables',
      icon: Icons.menu_book_outlined,
      tint: const Color(0xFFD97706),
      title: 'Cuentas por cobrar',
      value: s.receivablesTotal > 0
          ? '\$ ${formatCopHome(s.receivablesTotal)}'
          : 'Al día',
      subtitle: s.receivablesTotal > 0
          ? '${s.receivablesDebtors} cliente${s.receivablesDebtors == 1 ? '' : 's'} le debe${s.receivablesDebtors == 1 ? '' : 'n'}'
              '${s.receivablesOldestDays > 0 ? ' · el más antiguo hace ${s.receivablesOldestDays} días' : ''}'
          : 'Nadie le debe hoy',
      cta: 'Cuaderno de fiados ›',
      onTap: onFiados,
    ),
    LiveCardData(
      key: 'profit',
      icon: Icons.payments_outlined,
      tint: AppTheme.primary,
      title: 'Ganancia de hoy',
      value: s.salesCount > 0 ? '\$ ${formatCopHome(s.profitAmount)}' : '—',
      subtitle: s.salesCount > 0
          ? 'Margen ${s.profitMarginPct}%'
              '${s.shiftOpen ? ' · turno abierto' : ' · turno sin abrir'}'
          : 'Aún no hay ventas hoy',
      cta: 'Ganancias ›',
      onTap: onGanancias,
    ),
    if (hasOperation)
      LiveCardData(
        key: 'in_progress',
        icon: Icons.restaurant_outlined,
        tint: const Color(0xFF0D9668),
        title: 'En curso',
        value: s.inProgressTotal > 0 ? '${s.inProgressTotal} pedidos' : 'Nada',
        subtitle: s.inProgressTotal > 0
            ? '${s.inProgressTables} en mesas · ${s.inProgressOnline} en línea'
            : 'Sin pedidos abiertos',
        cta: 'Operación ›',
        onTap: onOperacion,
      ),
    LiveCardData(
      key: 'low_stock',
      icon: Icons.inventory_2_outlined,
      tint: const Color(0xFF2E5FD4),
      title: 'Stock bajo',
      value: s.lowStockCount > 0 ? '${s.lowStockCount} productos' : 'Completo',
      subtitle: s.lowStockCount > 0
          ? (s.lowStockExamples.isEmpty
              ? 'Revíselos antes de que se agoten'
              : '${s.lowStockExamples.take(2).join(', ')} y más por agotarse')
          : 'Nada por agotarse',
      cta: 'Inventario ›',
      onTap: onInventario,
    ),
    if (!hasOperation)
      LiveCardData(
        key: 'sales_count',
        icon: Icons.receipt_long_outlined,
        tint: const Color(0xFF0D9668),
        title: 'Ventas de hoy',
        value: '${s.salesCount}',
        subtitle: s.salesCount > 0
            ? 'Última hace poco — siga así'
            : 'Empiece con la primera venta',
        cta: 'Historial ›',
        onTap: onHistorial,
      ),
  ];
  return cards.take(4).toList(growable: false);
}

class LiveCards extends StatelessWidget {
  const LiveCards({super.key, required this.cards});

  final List<LiveCardData> cards;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: [
        for (final c in cards)
          InkWell(
            key: Key('live_card_${c.key}'),
            onTap: c.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x99D5E6F0)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x0F0E3450),
                      blurRadius: 10,
                      offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.tint.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(c.icon, size: 18, color: c.tint),
                  ),
                  const SizedBox(height: 8),
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                  Text(c.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary)),
                  Flexible(
                    child: Text(c.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5, color: Color(0xFF8AA2B2))),
                  ),
                  const SizedBox(height: 3),
                  Text(c.cta,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Movimientos de hoy (FR-07).
class MovementsList extends StatelessWidget {
  const MovementsList({super.key, required this.movements, this.onSeeAll});

  final List<Map<String, dynamic>> movements;
  final VoidCallback? onSeeAll;

  IconData _icon(String kind) {
    switch (kind) {
      case 'credit_payment':
        return Icons.menu_book_outlined;
      case 'online_order':
        return Icons.public_outlined;
      default:
        return Icons.shopping_cart_outlined;
    }
  }

  Color _tint(String kind) {
    switch (kind) {
      case 'credit_payment':
        return const Color(0xFFD97706);
      case 'online_order':
        return AppTheme.primary;
      default:
        return const Color(0xFF0D9668);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x99D5E6F0)),
        ),
        child: const Text('Aún no hay movimientos hoy. ¡La primera venta los estrena!',
            style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x99D5E6F0)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < movements.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFEEF4F8)),
            _row(movements[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> m) {
    final kind = (m['kind'] ?? '').toString();
    final amount = (m['amount'] as num?)?.toInt() ?? 0;
    final at = DateTime.tryParse((m['at'] ?? '').toString())?.toLocal();
    final hh = at == null
        ? ''
        : '${at.hour % 12 == 0 ? 12 : at.hour % 12}:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'a.m.' : 'p.m.'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _tint(kind).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_icon(kind), size: 18, color: _tint(kind)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((m['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(
                  [hh, (m['status'] ?? '').toString()]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF8AA2B2)),
                ),
              ],
            ),
          ),
          Text(
            '${amount >= 0 ? '+' : '−'}\$ ${formatCopHome(amount.abs())}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: kind == 'credit_payment'
                  ? const Color(0xFFD97706)
                  : const Color(0xFF0D9668),
            ),
          ),
        ],
      ),
    );
  }
}
