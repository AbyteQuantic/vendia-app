// Spec: specs/002-ordenes-compra/spec.md
//
// Widgets reutilizables del formulario de orden de compra (Feature 002).
// Extraídos de `purchase_order_form_screen.dart` para mantener cada
// archivo bajo el límite de 800 líneas (Constitución Art. IX).

import 'package:flutter/material.dart';

import '../../models/purchase_order.dart';
import '../../theme/app_theme.dart';

/// Una opción seleccionable de ítem: un insumo o un producto del tenant.
/// Encapsula el origen para que el formulario arme un `PurchaseOrderItem`
/// con la FK correcta (insumo XOR producto — D1).
class PurchaseItemSource {
  final String id;
  final String name;
  final bool isIngredient;
  final double unitCost;

  const PurchaseItemSource({
    required this.id,
    required this.name,
    required this.isIngredient,
    required this.unitCost,
  });
}

/// Bottom sheet para escoger un insumo o producto como ítem (UI_RULES §9).
class PurchaseSourcePickerSheet extends StatelessWidget {
  final List<PurchaseItemSource> sources;

  const PurchaseSourcePickerSheet({super.key, required this.sources});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escoja un producto',
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

/// Tarjeta de un ítem dentro del formulario de orden de compra.
class PurchaseItemCard extends StatelessWidget {
  final PurchaseOrderItem item;
  final String Function(double) money;
  final String Function(double) trim;
  final VoidCallback? onRemove;

  const PurchaseItemCard({
    super.key,
    required this.item,
    required this.money,
    required this.trim,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nameSnapshot,
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
                  '${trim(item.quantity)} × ${money(item.unitCost)} '
                  '= ${money(item.lineTotal)}',
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

/// Estado de error con botón Reintentar — UI_RULES §8.
class PurchaseFormErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const PurchaseFormErrorState({
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
