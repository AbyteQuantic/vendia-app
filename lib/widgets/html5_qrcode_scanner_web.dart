// Spec: hotfix scanner web — usa html5-qrcode (JS, self-hosted en
// `web/html5-qrcode.min.js`) inyectando el <div> directo al
// document.body en vez de HtmlElementView.
//
// PROBLEMA HISTÓRICO: Flutter web con renderer CanvasKit envuelve
// los HtmlElementView en un Shadow DOM con id propio. La lib
// html5-qrcode busca el div por `document.getElementById(id)` y no
// lo encuentra → falla con "HTML Element with id=... not found".
//
// SOLUCIÓN: NO usar HtmlElementView. Inyectar el <div id="h5q-X">
// directamente al `document.body` con `position: fixed`,
// `inset: 0`, `z-index: 999999` para que se renderee SOBRE el
// canvas WebGL de Flutter. El video llena la pantalla. Los
// controles (back, flash) se inyectan también como botones HTML
// dentro del mismo wrapper.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('Html5Qrcode')
extension type _Html5Qrcode._(JSObject _) implements JSObject {
  external _Html5Qrcode(String elementId);
  external JSPromise<JSAny?> start(
    JSAny cameraConfig,
    JSObject scanConfig,
    JSFunction onScanSuccess,
    JSFunction? onScanFailure,
  );
  external JSPromise<JSAny?> stop();
  external void clear();
}

class Html5QrcodeScannerWidget extends StatefulWidget {
  final void Function(String code) onDetected;
  final List<String>? formats;

  /// Callback opcional para el botón "atrás" inyectado en HTML —
  /// si es null, se cierra con Navigator.pop.
  final VoidCallback? onBack;

  const Html5QrcodeScannerWidget({
    super.key,
    required this.onDetected,
    this.formats,
    this.onBack,
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
  web.HTMLDivElement? _hostDiv;
  // Controles inyectados FUERA del host div (en document.body) para
  // que la librería html5-qrcode no los limpie cuando arranca —
  // antes vivían dentro de `_hostDiv` y la lib los tapaba con el
  // video, dejando al tendero sin forma de cancelar el escaneo.
  web.HTMLDivElement? _backBtnDiv;
  web.HTMLDivElement? _cancelBtnDiv;
  // Style tag inyectado en <head> para forzar fullscreen del <video>
  // que monta html5-qrcode (por defecto respeta aspect ratio de la
  // cámara → en iPhone vertical deja la mitad inferior negra).
  web.HTMLStyleElement? _styleElement;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _injectDom();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _injectDom() {
    // Wrapper full-screen sobre el canvas Flutter.
    final div = web.HTMLDivElement()
      ..id = _hostId
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.width = '100vw'
      ..style.height = '100vh'
      ..style.zIndex = '999999'
      ..style.backgroundColor = 'black'
      ..style.overflow = 'hidden';
    web.document.body!.append(div);
    _hostDiv = div;

    // Fuerza al <video> que html5-qrcode monta dentro de _hostDiv a
    // llenar TODA la pantalla con object-fit:cover. Sin esto el
    // video respeta su aspect-ratio (4:3 típico) y en iPhone vertical
    // (~9:19.5) deja la mitad inferior negra — el tendero ve una
    // ventanita arriba en vez de la cámara fullscreen.
    final style = web.HTMLStyleElement()
      ..textContent = '#$_hostId video{'
          'width:100vw !important;'
          'height:100vh !important;'
          'object-fit:cover !important;'
          'position:absolute !important;'
          'top:0 !important;'
          'left:0 !important;}'
          '#$_hostId > div{'
          'width:100% !important;'
          'height:100% !important;}';
    web.document.head!.append(style);
    _styleElement = style;

    // Corners + texto guía. Inyectados dentro del host (la lib
    // html5-qrcode los respeta porque no son children directos del
    // video). Los CONTROLES (back + Cancelar) van fuera del host,
    // en document.body, para que la lib no pueda taparlos.
    final guide = web.HTMLDivElement()
      ..innerHTML = '''
<div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none">
  <div style="width:260px;height:260px;position:relative">
    <div style="position:absolute;top:0;left:0;width:36px;height:36px;border-top:4px solid white;border-left:4px solid white;border-top-left-radius:4px"></div>
    <div style="position:absolute;top:0;right:0;width:36px;height:36px;border-top:4px solid white;border-right:4px solid white;border-top-right-radius:4px"></div>
    <div style="position:absolute;bottom:0;left:0;width:36px;height:36px;border-bottom:4px solid white;border-left:4px solid white;border-bottom-left-radius:4px"></div>
    <div style="position:absolute;bottom:0;right:0;width:36px;height:36px;border-bottom:4px solid white;border-right:4px solid white;border-bottom-right-radius:4px"></div>
  </div>
</div>
<div style="position:absolute;left:0;right:0;bottom:calc(env(safe-area-inset-bottom, 0px) + 120px);text-align:center;color:white;font-size:17px;font-weight:600;padding:0 24px;pointer-events:none;text-shadow:0 1px 3px rgba(0,0,0,0.6)">
  Apunte la cámara al código de barras del producto
</div>
'''
          .toJS
      ..style.position = 'absolute'
      ..style.inset = '0'
      ..style.pointerEvents = 'none'
      ..style.zIndex = '2';
    div.append(guide);

    _injectControls();
  }

  /// Botones de regresar/cancelar. Se appenden a `document.body`
  /// (NO al host div) con z-index `9999999` — encima del wrapper
  /// (`999999`) — para que sigan visibles aunque la librería
  /// html5-qrcode pinte el video tapando el host.
  void _injectControls() {
    // Back arrow arriba-izquierda (atajo rápido).
    final backBtn = web.HTMLDivElement()
      ..innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" '
              'viewBox="0 0 24 24" width="28" height="28" '
              'fill="white"><path d="M20 11H7.83l5.59-5.59L12 4l-8 '
              '8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>'
          .toJS
      ..style.position = 'fixed'
      ..style.top = 'calc(env(safe-area-inset-top, 0px) + 12px)'
      ..style.left = '12px'
      ..style.width = '52px'
      ..style.height = '52px'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.backgroundColor = 'rgba(0,0,0,0.65)'
      ..style.borderRadius = '26px'
      ..style.cursor = 'pointer'
      ..style.zIndex = '9999999';
    backBtn.onclick = ((web.MouseEvent _) => _handleBack()).toJS;
    web.document.body!.append(backBtn);
    _backBtnDiv = backBtn;

    // Botón CANCELAR grande abajo — el tendero 50+ necesita un
    // control evidente, no solo un icono pequeño arriba.
    final cancelBtn = web.HTMLDivElement()
      ..innerHTML = '<span style="color:white;font-size:20px;'
              'font-weight:700;letter-spacing:0.3px">Cancelar</span>'
          .toJS
      ..style.position = 'fixed'
      ..style.left = '20px'
      ..style.right = '20px'
      ..style.bottom = 'calc(env(safe-area-inset-bottom, 0px) + 24px)'
      ..style.height = '64px'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.backgroundColor = 'rgba(0,0,0,0.85)'
      ..style.border = '2px solid white'
      ..style.borderRadius = '16px'
      ..style.cursor = 'pointer'
      ..style.zIndex = '9999999'
      ..style.boxShadow = '0 4px 12px rgba(0,0,0,0.4)';
    cancelBtn.onclick = ((web.MouseEvent _) => _handleBack()).toJS;
    web.document.body!.append(cancelBtn);
    _cancelBtnDiv = cancelBtn;
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _start() {
    final hasLib =
        (web.window as JSObject).hasProperty('Html5Qrcode'.toJS).toDart;
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

      // Config minimalista — el ejemplo canónico de la doc de
      // html5-qrcode. Tras múltiples intentos con opciones avanzadas
      // (formats, videoConstraints HD, useBarCodeDetectorIfSupported),
      // alguna combinación rompe el scan. Volvemos al baseline para
      // confirmar primero que la decodificación funciona; después
      // optimizamos si hace falta.
      final cameraConfig = {'facingMode': 'environment'}.jsify()!;
      final scanConfig = {
        'fps': 10,
        'qrbox': {'width': 250, 'height': 250},
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
        final msg = err.toString();
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
      _showError('No se pudo iniciar el lector: $e');
    }
  }

  void _showError(String message) {
    if (_hostDiv == null) return;
    final err = web.HTMLDivElement()
      ..innerHTML = '''
<div style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;background:rgba(0,0,0,0.85);color:white;padding:0 32px;text-align:center">
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="56" height="56" fill="white"><path d="M21 6h-3.17L16 4h-6v2h5.12l1.83 2H21v12H5v-9H3v9c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zM8 14c0 2.76 2.24 5 5 5s5-2.24 5-5-2.24-5-5-5-5 2.24-5 5zm5-3c1.65 0 3 1.35 3 3s-1.35 3-3 3-3-1.35-3-3 1.35-3 3-3zM3.6 5L2.19 6.41 4.77 9H3v9c0 1.1.9 2 2 2h13.17l2.41 2.41L22 21l-2.5-2.5L3.6 5z"/></svg>
  <div style="margin-top:16px;font-size:17px;line-height:1.4">$message</div>
</div>
'''
          .toJS
      ..style.position = 'absolute'
      ..style.inset = '0'
      ..style.zIndex = '3';
    _hostDiv!.append(err);
    if (mounted) setState(() => _errorMessage = message);
  }

  @override
  void dispose() {
    final scanner = _scanner;
    if (scanner != null && _started) {
      scanner.stop().toDart.then((_) {
        try {
          scanner.clear();
        } catch (_) {}
        _removeDom();
      }).catchError((Object _) {
        try {
          scanner.clear();
        } catch (_) {}
        _removeDom();
        return null;
      });
    } else {
      _removeDom();
    }
    _scanner = null;
    super.dispose();
  }

  void _removeDom() {
    try {
      _hostDiv?.remove();
    } catch (_) {}
    try {
      _backBtnDiv?.remove();
    } catch (_) {}
    try {
      _cancelBtnDiv?.remove();
    } catch (_) {}
    try {
      _styleElement?.remove();
    } catch (_) {}
    _hostDiv = null;
    _backBtnDiv = null;
    _cancelBtnDiv = null;
    _styleElement = null;
  }

  @override
  Widget build(BuildContext context) {
    // Devolvemos un Container negro como background del Scaffold de
    // Flutter — el div HTML inyectado al body queda ENCIMA por el
    // z-index. El Flutter no participa visualmente del scanner.
    // Si hay error, también dibujamos un overlay Flutter (redundante
    // con el HTML) para que sea visible si el host div fue removido.
    final err = _errorMessage;
    return Container(
      color: Colors.black,
      child: err != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, height: 1.4),
                ),
              ),
            )
          : null,
    );
  }
}
