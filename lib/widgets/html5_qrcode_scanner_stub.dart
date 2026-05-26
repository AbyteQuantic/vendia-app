// Stub no-op para plataformas no-web. El import condicional
// (`if (dart.library.html) ...`) toma esta versión cuando no hay
// `dart:html` disponible. Móvil sigue usando mobile_scanner — este
// widget jamás se monta ahí.

import 'package:flutter/widgets.dart';

class Html5QrcodeScannerWidget extends StatelessWidget {
  final void Function(String code) onDetected;
  final List<String>? formats;

  const Html5QrcodeScannerWidget({
    super.key,
    required this.onDetected,
    this.formats,
  });

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // jamás llamado en móvil
}
