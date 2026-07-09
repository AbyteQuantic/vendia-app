// Spec: specs/102-completar-categorias-inventario/spec.md (FR-06)
//
// Selector de categoría (bottom sheet): chips de las categorías existentes
// del tenant + campo "Nueva categoría". Devuelve la categoría elegida — la
// escrita se normaliza contra las existentes (canonicalValue, Spec 068: no
// crear "Bebidas" y "bebidas" como distintas) — o null si se cierra sin
// elegir. Solo presentación: NO escribe nada (la vista que lo abre decide).

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';
import '../utils/text_normalize.dart';
import 'sku_manual_code_sheet.dart' show sheetHandle;

/// Abre el selector y devuelve la categoría elegida (o null).
Future<String?> showCategoryPickerSheet(
  BuildContext context, {
  required String title,
  required List<String> existing,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true, // que el teclado no tape el campo
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => CategoryPickerSheet(title: title, existing: existing),
  );
}

class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    super.key,
    required this.title,
    required this.existing,
  });

  final String title;

  /// Categorías ya usadas por el tenant (más las sugeridas por la IA en la
  /// sesión) — la reutilización va primero que la creación (FR-06).
  final List<String> existing;

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submitTyped() {
    final typed = _ctrl.text.trim();
    if (typed.isEmpty) return;
    // Duplicada con otra capitalización → reutiliza la grafía existente.
    Navigator.of(context).pop(canonicalValue(typed, widget.existing));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Que el teclado empuje el contenido, no lo tape.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetHandle(),
            Text(widget.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppUI.title),
            const SizedBox(height: AppUI.s16),
            if (widget.existing.isNotEmpty) ...[
              const Text('Sus categorías', style: AppUI.sectionLabel),
              const SizedBox(height: AppUI.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: AppUI.s8,
                    runSpacing: AppUI.s8,
                    children: [
                      for (final cat in widget.existing)
                        ActionChip(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(cat,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          labelStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.08),
                          side: BorderSide(
                              color: AppTheme.primary.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onPressed: () => Navigator.of(context).pop(cat),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppUI.s16),
            ],
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submitTyped(),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                hintText: 'Nueva categoría',
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: AppUI.s8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppUI.radius)),
              ),
            ),
            const SizedBox(height: AppUI.s12),
            AppButton(label: 'Usar esta categoría', onPressed: _submitTyped),
          ],
        ),
      ),
    );
  }
}
