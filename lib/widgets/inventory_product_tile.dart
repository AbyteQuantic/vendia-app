// Spec: specs/062-ui-highend-kit/spec.md
//
// Tile COMPACTO de producto para "Mi Inventario" (rediseño 2026-07-08 por
// feedback del fundador: las tarjetas anteriores ocupaban ~1/3 de pantalla
// con las 3 acciones regadas en una columna de IconButtons de 48dp c/u).
//
// Anatomía (fila ~92dp): miniatura 56dp redondeada · columna central con
// nombre a 2 líneas + fila precio/tag/StockBadge · a la derecha SOLO dos
// controles: Editar (acción principal, ≥44dp) y un menú ⋮ que agrupa
// Historial y Eliminar — eliminar deja de estar a un toque accidental
// (audiencia 50+) pero conserva su diálogo de confirmación en el caller.
//
// REGLA DE ORO del refactor visual (UI_RULES §12): cero cambios de lógica —
// mismos callbacks (onEdit/onDelete/onHistory), mismo swipe Dismissible con
// confirmación diferida al diálogo del caller.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';
import 'product_image.dart';
import 'stock_badge.dart';

/// Estilo del tag secundario (presentación · contenido, o SKU corto):
/// misma métrica de 12px medium que [MinimalBadge], en tinta suave del kit.
const TextStyle _tagStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: AppUI.inkSoft,
);

class InventoryProductTile extends StatelessWidget {
  const InventoryProductTile({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onDelete,
    this.onHistory,
  });

  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Sin nombre';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final stock = product['stock'] as int? ?? 0;
    final isMenuItem = product['is_menu_item'] == true;
    final byPortions = product['availability_mode'] == 'por_porciones';
    final photoUrl = product['photo_url'] as String?;
    final imageUrl = product['image_url'] as String?;
    final imgSrc =
        (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : imageUrl;
    final tag = _buildTag();

    return Dismissible(
      key: ValueKey(product['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppUI.s24),
        margin: const EdgeInsets.only(bottom: AppUI.s8),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(AppUI.radius),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        onDelete();
        return false; // el diálogo del caller decide la eliminación
      },
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onEdit();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: AppUI.s8),
          padding: const EdgeInsets.all(AppUI.s12),
          decoration: AppUI.card(),
          child: Row(
            children: [
              _thumb(imgSrc),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: AppUI.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppUI.s4),
                    Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _formatPrice(price),
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        if (tag.isNotEmpty) ...[
                          const SizedBox(width: AppUI.s8),
                          Flexible(
                            child: Text(
                              tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _tagStyle,
                            ),
                          ),
                        ],
                        const SizedBox(width: AppUI.s8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: StockBadge(
                              stock: stock,
                              size: StockBadgeSize.small,
                              isMenuItem: isMenuItem,
                              byPortions: byPortions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppUI.s4),
              _editButton(),
              _moreMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Tag secundario de la fila inferior: presentación · contenido si existen;
  /// si no, el SKU corto. "Plato de menú" ya lo comunica el [StockBadge].
  String _buildTag() {
    final presentation = (product['presentation'] as String? ?? '').trim();
    final content = (product['content'] as String? ?? '').trim();
    final pc = [presentation, content].where((s) => s.isNotEmpty).join(' · ');
    if (pc.isNotEmpty) return pc;
    final barcode = (product['barcode'] as String? ?? '').trim();
    return barcode.isEmpty ? '' : 'SKU $barcode';
  }

  Widget _thumb(String? imgSrc) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUI.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // Spec 090: caché en disco del thumbnail (listado de inventario).
      child: ProductImage(
        url: imgSrc,
        width: 56,
        height: 56,
        fit: BoxFit.contain,
        placeholder: const Center(
          child: Icon(Icons.inventory_2_outlined,
              size: 24, color: AppUI.inkSoft),
        ),
      ),
    );
  }

  /// Acción principal, visible y con objetivo táctil ≥44dp.
  Widget _editButton() {
    return IconButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        onEdit();
      },
      tooltip: 'Editar',
      icon: const Icon(Icons.edit_rounded, size: 20, color: AppTheme.primary),
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Menú ⋮ que agrupa las acciones secundarias/destructivas: Historial y
  /// Eliminar. Eliminar ya no queda a un toque directo sobre la lista.
  Widget _moreMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Más opciones',
      icon: const Icon(Icons.more_vert_rounded,
          size: 22, color: AppUI.inkSoft),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppUI.radius),
      ),
      onSelected: (value) {
        HapticFeedback.lightImpact();
        switch (value) {
          case 'history':
            onHistory?.call();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        if (onHistory != null)
          const PopupMenuItem(
            value: 'history',
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: AppUI.inkSoft),
                SizedBox(width: AppUI.s12),
                Text('Historial',
                    style: TextStyle(fontSize: 15, color: AppUI.ink)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppTheme.error),
              SizedBox(width: AppUI.s12),
              Text('Eliminar',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.error)),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatPrice(double price) {
    final int cents = price.round();
    final String s = cents.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }
}
