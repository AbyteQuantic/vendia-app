// Specs: 097-completar-fotos-inventario / 100-completar-skus-inventario
//
// Botón de acción COMPACTO para filas de acciones dentro de tarjetas
// (Completar fotos / Completar SKUs / Retocar fotos). El estilo es
// EXPLÍCITO completo (alto, texto, borde): el theme legacy de
// OutlinedButton (minimumSize double.infinity × 64, texto 22px) no
// participa, así que nunca se infla, se apila ni desborda a 360dp.
// Tap target 44dp (HIG/Material), label de UNA línea con ellipsis.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

class CompactActionButton extends StatelessWidget {
  const CompactActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppUI.s8),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUI.radius)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppUI.s4),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
