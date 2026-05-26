// Re-export que decide en tiempo de compilación qué implementación
// se carga del scanner web — la real (con js_interop) en web, un
// stub vacío en móvil.
//
// El consumidor importa SOLO este archivo:
//   import 'html5_qrcode_scanner.dart';
//
// y obtiene `Html5QrcodeScannerWidget` correcto para su plataforma.

export 'html5_qrcode_scanner_stub.dart'
    if (dart.library.js_interop) 'html5_qrcode_scanner_web.dart';
