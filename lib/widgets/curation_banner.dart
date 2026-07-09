// Spec: specs/102-completar-categorias-inventario/spec.md
//
// Banner de estado para las vistas de curaduría (Organizar categorías y
// hermanas): mensaje calmado + acción opcional. Tres usos en Spec 102:
// IA caída (modo manual), tope de 200 sugerencias del backend ("Pedir más
// sugerencias") y fallo de guardado ("Reintentar"). Solo presentación.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

class CurationBanner extends StatelessWidget {
  const CurationBanner({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;

  /// true → acento de error (rojo, texto fuerte); false → informativo suave.
  final bool error;

  /// Acción opcional (ej. "Reintentar"). null → solo mensaje.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppTheme.error : AppTheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: error
            ? AppTheme.error.withValues(alpha: 0.08)
            : AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(
            color: (error ? AppTheme.error : AppTheme.accent)
                .withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppUI.s8),
            Expanded(
              child: Text(message,
                  style: error ? AppUI.bodyStrong : AppUI.bodySoft),
            ),
          ]),
          if (actionLabel != null)
            Align(
              alignment: Alignment.centerRight,
              // TextButton con métricas explícitas del kit — el theme
              // legacy (60×60 / 20px) no participa.
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: Text(actionLabel!),
              ),
            ),
        ],
      ),
    );
  }
}
