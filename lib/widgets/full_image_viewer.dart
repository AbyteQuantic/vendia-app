// Spec: specs/017-ia-mejora-fiel-producto/spec.md
//
// Visor a pantalla completa con zoom (pellizco/doble-toque) para que el tendero
// AMPLÍE la imagen del producto — tanto su foto como la generada/mejorada por IA.
// Acepta un `child` (PickedImagePreview para foto local, Image.network/ProductImage
// para URL) y lo envuelve en InteractiveViewer.

import 'package:flutter/material.dart';

Future<void> showFullImageViewer(BuildContext context,
    {required Widget child}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false,
    builder: (ctx) {
      return Stack(
        children: [
          // Tocar el fondo cierra.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(child: child),
            ),
          ),
          // Botón cerrar.
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
                tooltip: 'Cerrar',
              ),
            ),
          ),
        ],
      );
    },
  );
}
