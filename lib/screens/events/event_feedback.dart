// Spec: specs/042-modulo-eventos/spec.md
//
// Helper de feedback (SnackBar) consistente y con buen estilo para el módulo
// de Eventos: flotante, redondeado, con color por tipo (éxito/error/info) e
// ícono. Reemplaza los SnackBars genéricos oscuros a pantalla completa.

import 'package:flutter/material.dart';

enum EventSnackKind { success, error, info }

void showEventSnack(
  BuildContext context,
  String message, {
  EventSnackKind kind = EventSnackKind.info,
}) {
  final (Color bg, IconData icon) = switch (kind) {
    EventSnackKind.success => (const Color(0xFF059669), Icons.check_circle_rounded),
    EventSnackKind.error => (const Color(0xFFDC2626), Icons.error_outline_rounded),
    EventSnackKind.info => (const Color(0xFF1E3A8A), Icons.info_outline_rounded),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        margin: const EdgeInsets.all(16),
        elevation: 4,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
}
