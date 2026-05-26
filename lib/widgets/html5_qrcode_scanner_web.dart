// Spec: hotfix scanner web — sustituye mobile_scanner en web por
// `html5-qrcode` (JS, CDN cargado en web/index.html). Solo se importa
// cuando hay `dart:js_interop` (browser).
//
// Usamos la clase `Html5Qrcode` (low-level, sin UI) en lugar de
// `Html5QrcodeScanner` (con UI propia + botón Request Permission).
// El low-level toma la cámara directo con `.start()` y deja que el
// caller dibuje su propio overlay (corners, texto, etc).

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
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
  // Mensaje visible para el dueño cuando el scanner web falla.
  // Null = todo OK. String = mostrar overlay con el problema.
  String? _errorMessage;

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
    // 0) Verificación dura: ¿la lib JS Html5Qrcode existe en window?
    // dart:js_interop_unsafe da hasProperty sobre JSObject.
    final hasLib = (web.window as JSObject)
        .hasProperty('Html5Qrcode'.toJS)
        .toDart;
    if (!hasLib) {
      _showError(
        'No se pudo cargar el lector. Verifique su conexión a '
        'internet y reintente.',
      );
      return;
    }

    try {
      final scanner = _Html5Qrcode(_hostId);
      _scanner = scanner;

      // facingMode 'environment' = cámara trasera en móvil.
      final cameraConfig = {'facingMode': 'environment'}.jsify()!;

      // qrbox: área central donde se hace el scan. fps: frames por
      // segundo (10 = balance CPU/detección).
      final scanConfig = {
        'fps': 10,
        'qrbox': {'width': 250, 'height': 250},
        'aspectRatio': 1.7777778, // 16:9 — se ajusta al video real
        if (widget.formats != null) 'formatsToSupport': widget.formats,
      }.jsify() as JSObject;

      void onSuccess(JSString code, JSAny? _) {
        widget.onDetected(code.toDart);
      }

      void onFailure(JSString _) {}

      final promise = scanner.start(
        cameraConfig,
        scanConfig,
        onSuccess.toJS,
        onFailure.toJS,
      );

      promise.toDart.then((_) {
        _started = true;
      }).catchError((Object err) {
        // Errores típicos:
        //   NotAllowedError → el usuario rechazó el permiso
        //   NotFoundError → no hay cámara en el dispositivo
        //   NotReadableError → la cámara está en uso por otra app
        //   OverconstrainedError → no se cumple facingMode
        final msg = err.toString();
        debugPrint('html5-qrcode start failed: $msg');
        if (msg.contains('NotAllowedError') ||
            msg.contains('Permission')) {
          _showError(
            'Cámara bloqueada. Toque la dirección en su navegador → '
            'Configuración del sitio → Permitir cámara, y reintente.',
          );
        } else if (msg.contains('NotFoundError')) {
          _showError('No se encontró cámara en este dispositivo.');
        } else if (msg.contains('NotReadableError')) {
          _showError(
            'La cámara está en uso por otra aplicación. Ciérrela y '
            'reintente.',
          );
        } else {
          _showError('No se pudo iniciar la cámara: $msg');
        }
        return null;
      });
    } catch (e) {
      debugPrint('html5-qrcode init failed: $e');
      _showError('No se pudo iniciar el lector: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
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
    final err = _errorMessage;
    return Stack(
      children: [
        HtmlElementView(viewType: _hostId),
        // Overlay visible solo cuando algo falla — el dueño SIEMPRE
        // sabe qué pasa en vez de quedar mirando una pantalla negra.
        if (err != null)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_rounded,
                        color: Colors.white, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      err,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
