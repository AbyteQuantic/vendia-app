// Spec: specs/046-impresora-usb-lan-escpos/spec.md
//
// Transport factory hub. Resolves to the native implementations (dart:io +
// USB/BT plugins) on Android/iOS/desktop, and to no-op stubs on web — so the
// web build never pulls dart:io or native plugins into dart2js.
export 'printer_transports_stub.dart'
    if (dart.library.io) 'printer_transports_io.dart';
