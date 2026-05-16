// Spec: specs/003-trabajos-muebles/spec.md
//
// Widgets y helpers reutilizables del módulo de trabajos (Feature 003).
// Extraídos de las pantallas para mantener cada archivo bajo el límite
// de 800 líneas (Constitución Art. IX).

import 'package:flutter/material.dart';

import '../../models/work_order.dart';
import '../../theme/app_theme.dart';

/// Formatea un monto en COP con separadores de miles — `$ 1.234.000`.
String workOrderMoney(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '\$ $buf';
}

/// Recorta el `.0` de cantidades enteras — `2` en vez de `2.0`.
String workOrderTrim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Color semántico de cada estado del ciclo de vida (DESIGN.md).
Color workOrderStatusColor(String status) {
  switch (status) {
    case WorkOrder.statusDelivered:
      return AppTheme.success;
    case WorkOrder.statusCanceled:
      return AppTheme.error;
    case WorkOrder.statusInProgress:
    case WorkOrder.statusApproved:
      return AppTheme.primaryLight;
    case WorkOrder.statusDone:
      return AppTheme.primary;
    default:
      return AppTheme.warning;
  }
}

/// Una opción seleccionable de material: un insumo o un producto del
/// tenant. Encapsula el origen para que el formulario arme un
/// `WorkOrderItem` con la FK correcta (insumo XOR producto — FR-02).
class WorkMaterialSource {
  final String id;
  final String name;
  final bool isIngredient;
  final double unitCost;

  const WorkMaterialSource({
    required this.id,
    required this.name,
    required this.isIngredient,
    required this.unitCost,
  });
}

/// Chip de estado con su color semántico.
class WorkOrderStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const WorkOrderStatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Tarjeta de un ítem (material o mano de obra) dentro del formulario.
class WorkItemCard extends StatelessWidget {
  final WorkOrderItem item;
  final VoidCallback? onRemove;

  const WorkItemCard({
    super.key,
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            item.isMaterial
                ? Icons.inventory_2_rounded
                : Icons.construction_rounded,
            color: AppTheme.primary,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.kindLabel} · '
                  '${workOrderTrim(item.quantity)} × '
                  '${workOrderMoney(item.unitPrice)} '
                  '= ${workOrderMoney(item.lineTotal)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppTheme.error, size: 26),
              tooltip: 'Quitar',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet para escoger un insumo o producto como material
/// (UI_RULES §9 — listas largas en bottom sheet).
class WorkMaterialPickerSheet extends StatelessWidget {
  final List<WorkMaterialSource> sources;

  const WorkMaterialPickerSheet({super.key, required this.sources});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escoja un material',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sources.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppTheme.borderColor, height: 1),
              itemBuilder: (_, i) {
                final s = sources[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    s.isIngredient
                        ? Icons.kitchen_rounded
                        : Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                    size: 26,
                  ),
                  title: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    s.isIngredient ? 'Insumo' : 'Producto',
                    style: const TextStyle(
                        fontSize: 18, color: AppTheme.textSecondary),
                  ),
                  onTap: () => Navigator.of(context).pop(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de error con botón Reintentar — UI_RULES §8.
class WorkOrderErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const WorkOrderErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 72, color: AppTheme.borderColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 64,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
                child: const Text(
                  'Reintentar',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
