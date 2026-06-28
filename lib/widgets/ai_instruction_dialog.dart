// Spec: specs/017-ia-mejora-fiel-producto/spec.md — FR-05
//
// Diálogo para que el tendero escriba indicaciones a la IA cuando el resultado
// salió alterado. El texto se envía como guía para reintentar la mejora.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

/// Pide una indicación escrita para corregir la mejora de la foto.
/// Devuelve el texto (no vacío) o null si se cancela.
Future<String?> showAiInstructionDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUI.radius)),
      title: const Text('Corregir con la IA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escriba qué debe ajustar la IA. Ella respetará su producto: '
            'no lo cambia, solo mejora la foto.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: AppUI.s12),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'Ej.: deje la tapa roja · no cambie el empaque · céntrelo mejor',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final t = ctrl.text.trim();
            Navigator.pop(ctx, t.isEmpty ? null : t);
          },
          child: const Text('Aplicar'),
        ),
      ],
    ),
  );
}
