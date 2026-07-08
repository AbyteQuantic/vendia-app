// Spec: specs/094-foto-fiel-fondo-realce/spec.md
//
// Hoja (bottom sheet) unificada "¿Qué desea hacer?" para las opciones de
// mejorar/crear la imagen de un producto con IA. Antes vivía inline en el
// formulario de edición (manage_inventory_screen). Se extrajo para reutilizarla
// en creación (create_product_screen) y en el review masivo (ia_result_screen),
// y para arreglar que se cortaba abajo en pantallas chicas.
//
// Orden fijo de opciones (Spec 094/017):
//   1. Quitar fondo      (solo con foto)
//   2. Mejorar con IA    (solo con foto)
//   3. Generar imagen nueva  (siempre)
//   4. Corregir con indicaciones (opcional, solo con foto)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'catalog_photo_suggestion.dart';

/// Muestra la hoja unificada de opciones de IA para la foto de un producto.
///
/// - [hasPhoto] controla si aparecen "Quitar fondo"/"Mejorar con IA" (y la
///   opción de indicaciones). Sin foto solo se muestra "Generar imagen nueva".
/// - [onInstructions] `null` → no se muestra "Corregir con indicaciones".
/// - [onAcceptCatalog] `null` (o [barcode] vacío) → no se muestra la sugerencia
///   de foto verificada de catálogo (Spec 096).
Future<void> showAiPhotoOptions(
  BuildContext context, {
  required String name,
  required String presentation,
  required String content,
  required bool hasPhoto,
  String barcode = '',
  required VoidCallback onRemoveBg,
  required VoidCallback onImprove,
  required VoidCallback onGenerate,
  VoidCallback? onInstructions,
  ValueChanged<String>? onAcceptCatalog,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // ARREGLA EL CORTE: sin esto la hoja se limita a ~la mitad de la pantalla
    // y "Generar imagen nueva" / "Corregir con indicaciones" quedaban fuera.
    isScrollControlled: true,
    builder: (ctx) {
      final trimmedName = name.trim();
      final trimmedPres = presentation.trim();
      final trimmedContent = content.trim();
      final subtitle = 'Nombre: $trimmedName\n'
          'Presentación: $trimmedPres · $trimmedContent';

      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // Acota el alto: en pantallas chicas se hace scroll y NUNCA se corta
        // la última tarjeta. viewPaddingOf respeta el safe area (home bar).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, 24 + MediaQuery.viewPaddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('¿Qué desea hacer?',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              // Spec 096 — sugerencia OPCIONAL de foto verificada de catálogo
              // (Open Food Facts) para el barcode. Nunca reemplaza ni se aplica
              // sola; NO toca las opciones de abajo.
              if (onAcceptCatalog != null && barcode.trim().isNotEmpty)
                CatalogPhotoSuggestion(
                  barcode: barcode.trim(),
                  onAccept: (url) {
                    Navigator.of(ctx).pop();
                    onAcceptCatalog(url);
                  },
                ),
              // Spec 094: el tendero elige — quitar fondo (deja el producto
              // igual) o mejorar con IA (limpia/mejora, puede cambiar detalles).
              if (hasPhoto) ...[
                AiOptionTile(
                  icon: Icons.auto_fix_high_rounded,
                  color: const Color(0xFF3B82F6),
                  title: 'Quitar fondo',
                  subtitle:
                      'Deja su producto igual sobre fondo blanco de estudio',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onRemoveBg();
                  },
                ),
                const SizedBox(height: 12),
                AiOptionTile(
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFF0E7490),
                  title: 'Mejorar con IA',
                  subtitle:
                      'Limpia y mejora el producto (puede cambiar detalles)',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onImprove();
                  },
                ),
                const SizedBox(height: 12),
              ],
              AiOptionTile(
                icon: Icons.add_photo_alternate_rounded,
                color: const Color(0xFF7C3AED),
                title: 'Generar imagen nueva',
                subtitle:
                    'Crea una imagen desde cero basada en el nombre y presentación',
                onTap: () {
                  Navigator.of(ctx).pop();
                  onGenerate();
                },
              ),
              // Spec 017 FR-05: corregir un resultado alterado con indicaciones
              // escritas. Solo si ya hay una foto que mejorar.
              if (onInstructions != null && hasPhoto) ...[
                const SizedBox(height: 12),
                AiOptionTile(
                  icon: Icons.edit_note_rounded,
                  color: const Color(0xFF0E6BA8),
                  title: 'Corregir con indicaciones',
                  subtitle: 'Dígale a la IA qué ajustar (respeta su producto)',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onInstructions();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Tarjeta de una opción de IA dentro de [showAiPhotoOptions].
class AiOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const AiOptionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 26),
          ],
        ),
      ),
    );
  }
}
