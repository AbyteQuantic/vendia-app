// Spec: hotfix scanner web — sustituye mobile_scanner en web por
// `html5-qrcode` (JS, CDN cargado en web/index.html). Solo se importa
// cuando hay `dart:js_interop` (browser).
//
// Usamos la clase `Html5Qrcode` (low-level, sin UI) en lugar de
// `Html5QrcodeScanner` (con UI propia + botón Request Permission).
// El low-level toma la cámara directo con `.start()` y deja que el
// caller dibuje su propio overlay (corners, texto, etc).

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Bindings JS mínimos para `Html5Qrcode` (lib global cargada desde
/// el CDN en `web/index.html`). NOTA: la clase es `Html5Qrcode` —
/// sin "Scanner" al final. La variante "Scanner" tiene UI propia.
@JS('Html5Qrcode')
extension type _Html5Qrcode._(JSObject _) implements JSObject {
  external _Html5Qrcode(String elementId);

  /// Inicia la cámara. `cameraConfig` puede ser string deviceId o
  /// `{facingMode: 'environment'}` object. Devuelve una Promise.
  external JSPromise<JSAny?> start(
    JSAny cameraConfig,
    JSObject scanConfig,
    JSFunction onScanSuccess,
    JSFunction? onScanFailure,
  );

  /// Detiene la cámara. Idempotente.
  external JSPromise<JSAny?> stop();

  /// Libera recursos del DOM. Llamar tras stop().
  external void clear();
}

class Html5QrcodeScannerWidget extends StatefulWidget {
  /// Callback con el código detectado.
  final void Function(String code) onDetected;

  /// Formatos opcionales (string como 'EAN_13', 'CODE_128', etc).
  /// Si null, html5-qrcode acepta todos.
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
  late final String _hostId =
      'h5q-${DateTime.now().microsecondsSinceEpoch}';

  _Html5Qrcode? _scanner;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _registerViewFactory();
    // Espera al post-frame para que el <div> exista en DOM.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _registerViewFactory() {
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _hostId,
      (int viewId) {
        final div = web.HTMLDivElement()
          ..id = _hostId
          ..style.width = '100%'
          ..style.height = '100%'
          // El video que html5-qrcode injecta es 100% width por default;
          // forzamos object-fit: cover para que llene el área sin
          // bandas negras (UX igual que mobile_scanner).
          ..style.backgroundColor = 'black';
        return div;
      },
    );
  }

  void _start() {
    try {
      final scanner = _Html5Qrcode(_hostId);
      _scanner = scanner;

      // facingMode 'environment' = cámara trasera en móvil.
      final cameraConfig = {'facingMode': 'environment'}.jsify()!;

      // qrbox: área central donde se hace el scan. fps: frames por
      // segundo (10 = balance CPU/detección). disableFlip: false
      // permite leer códigos al revés.
      final scanConfig = {
        'fps': 10,
        'qrbox': {'width': 250, 'height': 250},
        'aspectRatio': 1.7777778, // 16:9 — se ajusta al video real
        if (widget.formats != null) 'formatsToSupport': widget.formats,
      }.jsify() as JSObject;

      void onSuccess(JSString code, JSAny? _) {
        widget.onDetected(code.toDart);
      }

      // onFailure se invoca en CADA frame sin match — ruido normal,
      // pasamos un noop. NO puede ser null, html5-qrcode lo invoca.
      void onFailure(JSString _) {}

      final promise = scanner.start(
        cameraConfig,
        scanConfig,
        onSuccess.toJS,
        onFailure.toJS,
      );

      // `.start()` devuelve Promise — esperamos para capturar errores
      // (denial de permisos, no hay cámara, etc) y poder loggear.
      promise.toDart.then((_) {
        _started = true;
      }).catchError((Object err) {
        // Falló — typicamente NotAllowedError (permiso denegado) o
        // NotFoundError (sin cámara). Por ahora silencioso; el área
        // queda negra y el dueño ve que no hay video.
        debugPrint('html5-qrcode start failed: $err');
        return null;
      });
    } catch (e) {
      // Lib no cargada o JS exception sincrónica.
      debugPrint('html5-qrcode init failed: $e');
    }
  }

  @override
  void dispose() {
    final scanner = _scanner;
    if (scanner != null && _started) {
      // stop() es Promise; llamamos clear() después en el .then.
      // Si falla, igual liberamos refs.
      scanner.stop().toDart.then((_) {
        try {
          scanner.clear();
        } catch (_) {}
      }).catchError((Object _) {
        try {
          scanner.clear();
        } catch (_) {}
        return null;
      });
    }
    _scanner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _hostId);
  }
}
