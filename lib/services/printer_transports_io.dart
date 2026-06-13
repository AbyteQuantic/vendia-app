// Spec: specs/046-impresora-usb-lan-escpos/spec.md
//
// Native (Android/iOS/desktop) transports. Only compiled when dart:io is
// available — the web build resolves to printer_transports_stub.dart via the
// conditional export in printer_transports.dart, so this file's dart:io /
// plugin imports never reach the dart2js output.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:usb_serial/usb_serial.dart';

import 'printer_config.dart';
import 'printer_transport.dart';

/// Factory: build the right transport for [config]. The returned instance is
/// stateful (owns the live connection) and is reused by HardwareService until
/// the user picks a different printer.
PrinterTransport buildTransport(PrinterConfig config) => switch (config.type) {
      PrinterConnectionType.bluetooth => BluetoothPrinterTransport(),
      PrinterConnectionType.network => TcpPrinterTransport(),
      PrinterConnectionType.usb => UsbPrinterTransport(),
    };

// ─────────────────────────────── Bluetooth ──────────────────────────────────

/// Wraps flutter_bluetooth_serial. Holds a single BluetoothConnection. The
/// library leaks stale sockets if you forget to close them, so we null
/// [_connection] on every disconnect/error path.
class BluetoothPrinterTransport implements PrinterTransport {
  BluetoothConnection? _connection;

  @override
  Future<bool> connect(String address) async {
    if (_connection?.isConnected == true) return true;
    if (_connection != null) {
      try {
        await _connection!.close();
      } catch (_) {
        // already closed — ignore
      }
      _connection = null;
    }
    try {
      _connection = await BluetoothConnection.toAddress(address);
      return _connection?.isConnected == true;
    } catch (_) {
      _connection = null;
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    final c = _connection;
    _connection = null;
    if (c == null) return true;
    try {
      await c.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isConnected() async => _connection?.isConnected == true;

  @override
  Future<List<PrinterDeviceInfo>> bondedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return devices
          .map((d) => (
                name: (d.name ?? '').isEmpty ? d.address : d.name!,
                address: d.address,
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    final c = _connection;
    if (c == null || !c.isConnected) {
      throw StateError('Bluetooth socket is not open');
    }
    c.output.add(Uint8List.fromList(bytes));
    await c.output.allSent;
  }
}

// ──────────────────────────────── Network ───────────────────────────────────

/// Raw TCP transport for ESC/POS network printers (JetDirect / RAW, port
/// 9100). [address] is "ip:port"; the port defaults to 9100. No discovery —
/// the user types the printer's IP (printed on the printer's self-test page).
class TcpPrinterTransport implements PrinterTransport {
  Socket? _socket;

  @override
  Future<bool> connect(String address) async {
    await disconnect();
    final raw = address.trim();
    final idx = raw.lastIndexOf(':');
    final host = idx > 0 ? raw.substring(0, idx) : raw;
    final port =
        idx > 0 ? (int.tryParse(raw.substring(idx + 1)) ?? 9100) : 9100;
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      return true;
    } catch (_) {
      _socket = null;
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    final s = _socket;
    _socket = null;
    if (s == null) return true;
    try {
      await s.flush().timeout(const Duration(seconds: 2), onTimeout: () {});
      await s.close();
      s.destroy();
      return true;
    } catch (_) {
      try {
        s.destroy();
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<bool> isConnected() async => _socket != null;

  @override
  Future<List<PrinterDeviceInfo>> bondedDevices() async => const [];

  @override
  Future<void> write(List<int> bytes) async {
    final s = _socket;
    if (s == null) throw StateError('TCP socket is not open');
    s.add(bytes);
    await s.flush();
  }
}

// ────────────────────────────────── USB ─────────────────────────────────────

/// USB transport via the usb_serial plugin. [address] is "vid:pid" (decimal)
/// so it survives re-attach (the OS deviceId changes each plug-in). Works for
/// printers that expose a CDC/serial interface — the common case for the
/// DigitalPOS DIG-E200I USB variant. Pure printer-class (bulk-only) devices
/// that usb_serial cannot open will fail [connect] cleanly (returns false),
/// and the user can fall back to the LAN port.
class UsbPrinterTransport implements PrinterTransport {
  UsbPort? _port;

  static String _key(UsbDevice d) => '${d.vid}:${d.pid}';

  @override
  Future<bool> connect(String address) async {
    await disconnect();
    try {
      final devices = await UsbSerial.listDevices();
      if (devices.isEmpty) return false;
      final want = address.trim();
      final device = devices.firstWhere(
        (d) => _key(d) == want,
        orElse: () => devices.first,
      );
      final port = await device.create();
      if (port == null) return false;
      final opened = await port.open();
      if (!opened) return false;
      // Harmless for CDC printers; ignored by printer-class endpoints.
      await port.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      _port = port;
      return true;
    } catch (_) {
      _port = null;
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    final p = _port;
    _port = null;
    if (p == null) return true;
    try {
      await p.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isConnected() async => _port != null;

  @override
  Future<List<PrinterDeviceInfo>> bondedDevices() async {
    try {
      final devices = await UsbSerial.listDevices();
      return devices
          .map((d) => (
                name: (d.productName ?? '').isNotEmpty
                    ? d.productName!
                    : 'USB ${_key(d)}',
                address: _key(d),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    final p = _port;
    if (p == null) throw StateError('USB port is not open');
    await p.write(Uint8List.fromList(bytes));
  }
}
