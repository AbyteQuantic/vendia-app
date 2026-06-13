// Spec: specs/046-impresora-usb-lan-escpos/spec.md
import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Physical transport the app uses to reach the thermal printer.
///
/// The DigitalPOS DIG-E200I (and most ESC/POS 80mm printers) ships in
/// USB + LAN variants; cheaper field printers are Bluetooth. We support
/// all three so the same APK runs on the SAT N140 all-in-one (USB/LAN)
/// and on a tendero's phone paired to a pocket BT printer.
enum PrinterConnectionType { bluetooth, usb, network }

extension PrinterConnectionTypeX on PrinterConnectionType {
  String get wire => switch (this) {
        PrinterConnectionType.bluetooth => 'bluetooth',
        PrinterConnectionType.usb => 'usb',
        PrinterConnectionType.network => 'network',
      };

  /// Human label for the picker (Spanish, gerontodiseño).
  String get label => switch (this) {
        PrinterConnectionType.bluetooth => 'Bluetooth',
        PrinterConnectionType.usb => 'USB (cable)',
        PrinterConnectionType.network => 'Red (Wi-Fi/LAN)',
      };

  static PrinterConnectionType fromWire(String? s) => switch (s) {
        'usb' => PrinterConnectionType.usb,
        'network' => PrinterConnectionType.network,
        _ => PrinterConnectionType.bluetooth,
      };
}

/// Default raw port for ESC/POS network printers (JetDirect / RAW 9100).
const int kDefaultPrinterPort = 9100;

/// A fully resolved printer selection: which transport, how to reach it,
/// a human name for the UI, and the paper width so the receipt is laid
/// out for the right column count (80mm = 72mm print area = 48 cols).
///
/// Immutable — [copyWith] returns a new instance (workspace coding rule).
class PrinterConfig {
  const PrinterConfig({
    required this.type,
    required this.address,
    required this.name,
    this.paperSize = PaperSize.mm80,
  });

  /// Transport selector.
  final PrinterConnectionType type;

  /// Transport-specific address:
  ///   - bluetooth → MAC (e.g. "00:11:22:33:44:55")
  ///   - usb       → device identifier (vid:pid or device name)
  ///   - network   → "ip:port" (e.g. "192.168.1.50:9100")
  final String address;

  /// Friendly name shown in the UI.
  final String name;

  /// Paper width. The DIG-E200I is 80mm; pocket BT printers are usually 58mm.
  final PaperSize paperSize;

  bool get isBluetooth => type == PrinterConnectionType.bluetooth;
  bool get isUsb => type == PrinterConnectionType.usb;
  bool get isNetwork => type == PrinterConnectionType.network;

  /// For network configs, split [address] into host + port. Falls back to
  /// [kDefaultPrinterPort] when the port is missing or unparseable.
  ({String host, int port}) get networkEndpoint {
    final raw = address.trim();
    final idx = raw.lastIndexOf(':');
    if (idx <= 0) return (host: raw, port: kDefaultPrinterPort);
    final host = raw.substring(0, idx);
    final port = int.tryParse(raw.substring(idx + 1)) ?? kDefaultPrinterPort;
    return (host: host, port: port);
  }

  PrinterConfig copyWith({
    PrinterConnectionType? type,
    String? address,
    String? name,
    PaperSize? paperSize,
  }) =>
      PrinterConfig(
        type: type ?? this.type,
        address: address ?? this.address,
        name: name ?? this.name,
        paperSize: paperSize ?? this.paperSize,
      );

  Map<String, dynamic> toJson() => {
        'type': type.wire,
        'address': address,
        'name': name,
        'paper': paperSize == PaperSize.mm58 ? 'mm58' : 'mm80',
      };

  static PrinterConfig? fromJson(Map<String, dynamic> m) {
    final address = (m['address'] as String?)?.trim() ?? '';
    if (address.isEmpty) return null;
    return PrinterConfig(
      type: PrinterConnectionTypeX.fromWire(m['type'] as String?),
      address: address,
      name: (m['name'] as String?)?.trim().isNotEmpty == true
          ? (m['name'] as String).trim()
          : address,
      paperSize: (m['paper'] as String?) == 'mm58'
          ? PaperSize.mm58
          : PaperSize.mm80,
    );
  }

  String encode() => jsonEncode(toJson());

  static PrinterConfig? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return fromJson(m);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PrinterConfig &&
      other.type == type &&
      other.address == address &&
      other.name == name &&
      other.paperSize == paperSize;

  @override
  int get hashCode => Object.hash(type, address, name, paperSize);
}
