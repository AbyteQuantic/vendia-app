// Stub no-op para plataformas no-web. El import condicional
// (`if (dart.library.html) ...`) toma esta versión cuando no hay
// `dart:html` disponible. Móvil sigue usando mobile_scanner — este
// widget jamás se monta ahí.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

class Html5QrcodeScannerWidget extends StatelessWidget {
  final void Function(String code) onDetected;
  final List<String>? formats;

  /// Visibilidad controlada por el padre (solo web): false = pausar la
  /// cámara y ocultar el video HTML para que los diálogos Flutter (p. ej.
  /// "Código no reconocido") sean visibles. En móvil se ignora.
  final ValueListenable<bool>? visibility;

  const Html5QrcodeScannerWidget({
    super.key,
    required this.onDetected,
    this.formats,
    this.visibility,
  });

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // jamás llamado en móvil
}
