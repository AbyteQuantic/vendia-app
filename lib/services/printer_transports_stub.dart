// Spec: specs/046-impresora-usb-lan-escpos/spec.md
//
// Web fallback. dart:io sockets, USB host, and the Bluetooth serial plugin
// do not exist in the browser, so on web every transport is a no-op that
// fails gracefully. The POS hardware path only runs on the Android terminal;
// the web build just needs to COMPILE without pulling dart:io / native
// plugins into the dart2js output.
import 'printer_config.dart';
import 'printer_transport.dart';

PrinterTransport buildTransport(PrinterConfig config) =>
    const _UnsupportedTransport();

class _UnsupportedTransport implements PrinterTransport {
  const _UnsupportedTransport();

  @override
  Future<bool> connect(String address) async => false;

  @override
  Future<bool> disconnect() async => true;

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<List<PrinterDeviceInfo>> bondedDevices() async => const [];

  @override
  Future<void> write(List<int> bytes) async =>
      throw StateError('La impresión no está disponible en la web.');
}
