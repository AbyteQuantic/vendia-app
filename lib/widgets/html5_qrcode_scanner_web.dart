// Spec: hotfix scanner web — sustituye mobile_scanner en web por
// `html5-qrcode` (JS, CDN cargado en web/index.html). Solo se importa
// cuando `kIsWeb` — la lib JS no existe en móvil.
//
// Razón: mobile_scanner ^7 con motor zxing-wasm sigue fallando en
// Safari iOS para muchos códigos retail. `html5-qrcode` (Google ZXing
// JS port mantenido por mebjas) es la lib más probada en producción
// para escaneo desde el browser y Safari iOS lo soporta correctamente.

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Bindings JS mínimos para `Html5QrcodeScanner` (lib global cargada
/// desde el CDN en `web/index.html`).
@JS('Html5QrcodeScanner')
extension type _Html5QrcodeScanner._(JSObject _) implements JSObject {
  external _Html5QrcodeScanner(
      String elementId, JSObject config, bool verbose);

  external void render(JSFunction onSuccess, JSFunction onError);

  external JSPromise<JSAny?> clear();
}

/// Widget que muestra el lector `html5-qrcode` y emite el código
/// detectado vía [onDetected]. Cubre el caso web (kIsWeb) — móvil
/// no usa este widget, ahí sigue mobile_scanner.
class Html5QrcodeScannerWidget extends StatefulWidget {
  /// Callback con el valor crudo del barcode/QR cuando se detecta.
  final void Function(String code) onDetected;

  /// Lista opcional de formatos. Si no se pasa, html5-qrcode acepta
  /// todos (el filtrado se hace al matchear contra el catálogo).
  final List<String>? formats;

  const Html5QrcodeScannerWidget({
    super.key,
    required this.onDetected,
    this.formats,
  });

  @override
  State<Html5QrcodeScannerWidget> createState() =>
      _Html5QrcodeScannerWidgetState();
}

class _Html5QrcodeScannerWidgetState
    extends State<Html5QrcodeScannerWidget> {
  // ID único del <div> que html5-qrcode controla. Cada instancia del
  // widget debe tener uno distinto para evitar colisiones si por
  // alguna razón se montan dos a la vez (no debería pasar, pero
  // estamos a salvo).
  late final String _hostId =
      'h5q-scanner-${DateTime.now().microsecondsSinceEpoch}';

  _Html5QrcodeScanner? _scanner;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _registerViewFactory();
    // Espera al próximo frame para que el div esté en el DOM antes
    // de inicializar el scanner JS.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _registerViewFactory() {
    if (_registered) return;
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _hostId,
      (int viewId) {
        final div = web.HTMLDivElement()
          ..id = _hostId
          ..style.width = '100%'
          ..style.height = '100%';
        return div;
      },
    );
    _registered = true;
  }

  void _start() {
    try {
      // Config recomendada por la lib para retail/QR:
      //   fps: 10   → balance entre detección y CPU
      //   qrbox: 250 → área central de detección
      //   aspectRatio: 1.333 (4:3) → marcos típicos de tienda
      final config = {
        'fps': 10,
        'qrbox': {'width': 250, 'height': 250},
        'aspectRatio': 1.333,
        // Permitir cámara trasera por default en móvil.
        'videoConstraints': {
          'facingMode': 'environment',
        },
        if (widget.formats != null) 'formatsToSupport': widget.formats,
      }.jsify() as JSObject;

      final scanner = _Html5QrcodeScanner(_hostId, config, false);
      _scanner = scanner;

      // Callbacks: success(code, result) — fire de inmediato.
      // failure(err) — silencioso (es ruido normal cuando no hay match).
      scanner.render(
        (JSString code, JSAny? _) {
          widget.onDetected(code.toDart);
        }.toJS,
        (JSString _) {
          // Silencioso — html5-qrcode invoca onError en cada frame que
          // no encuentra nada. Inundaría logs si lo propagamos.
        }.toJS,
      );
    } catch (_) {
      // Si Html5QrcodeScanner no está en window (script no cargó o
      // bloqueado), no podemos hacer mucho — el caller verá un div
      // vacío. En producción esto no debería pasar; el script se
      // carga sincrónicamente desde el <head>.
    }
  }

  @override
  void dispose() {
    // Para Html5QrcodeScanner, .clear() devuelve una Promise — la
    // disparamos pero no esperamos (estamos en dispose).
    try {
      _scanner?.clear();
    } catch (_) {}
    _scanner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _hostId);
  }
}
