import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/format_cop.dart';
import '../tables_controller.dart';

class TableCard extends StatelessWidget {
  final TableTab tab;
  final VoidCallback onTap;

  const TableCard({super.key, required this.tab, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOccupied = tab.isOpen;
    final color = isOccupied ? AppTheme.error : AppTheme.success;
    final timeOpen = isOccupied
        ? _formatDuration(DateTime.now().difference(tab.openedAt))
        : '';

    return Semantics(
      button: true,
      label:
          'Mesa ${tab.tableNumber}, ${isOccupied ? "ocupada, total ${formatCOP(tab.total)}" : "libre"}',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 80, minWidth: 80),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOccupied
                    ? Icons.table_restaurant_rounded
                    : Icons.add_circle_outline_rounded,
                color: color,
                size: 32,
              ),
              const SizedBox(height: 6),
              Text(
                'Mesa ${tab.tableNumber}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (isOccupied) ...[
                const SizedBox(height: 4),
                Text(
                  formatCOP(tab.total),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  timeOpen,
                  style: TextStyle(
                    fontSize: 18,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return 'Recién abierta';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}
