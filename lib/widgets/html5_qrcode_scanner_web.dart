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

    // Botón back HTML (porque el back del Scaffold queda debajo del
    // wrapper en z-index). Posicionado arriba-izquierda con SafeArea
    // emulado (padding 12 + 12).
    final btn = web.HTMLDivElement()
      ..innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" '
              'viewBox="0 0 24 24" width="28" height="28" '
              'fill="white"><path d="M20 11H7.83l5.59-5.59L12 4l-8 '
              '8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>'
          .toJS
      ..style.position = 'absolute'
      ..style.top = 'calc(env(safe-area-inset-top, 0px) + 12px)'
      ..style.left = '12px'
      ..style.width = '48px'
      ..style.height = '48px'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.backgroundColor = 'rgba(0,0,0,0.45)'
      ..style.borderRadius = '24px'
      ..style.cursor = 'pointer'
      ..style.zIndex = '1';
    btn.onclick = ((web.MouseEvent _) {
      if (widget.onBack != null) {
        widget.onBack!();
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    }).toJS;
    div.append(btn);

    // Corners + texto guía. Inyectados como HTML estático para no
    // depender del Flutter canvas.
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
<div style="position:absolute;left:0;right:0;bottom:calc(env(safe-area-inset-bottom, 0px) + 48px);text-align:center;color:white;font-size:17px;font-weight:600;padding:0 24px;pointer-events:none;text-shadow:0 1px 3px rgba(0,0,0,0.6)">
  Apunte la cámara al código de barras del producto
</div>
'''
          .toJS
      ..style.position = 'absolute'
      ..style.inset = '0'
      ..style.pointerEvents = 'none'
      ..style.zIndex = '2';
    div.append(guide);
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

      final cameraConfig = {'facingMode': 'environment'}.jsify()!;
      final scanConfig = {
        'fps': 10,
        'qrbox': {'width': 260, 'height': 260},
        'aspectRatio': 1.7777778,
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
    _hostDiv = null;
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
