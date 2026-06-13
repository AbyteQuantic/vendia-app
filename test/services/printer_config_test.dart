// Spec: specs/046-impresora-usb-lan-escpos/spec.md
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/printer_config.dart';

void main() {
  group('PrinterConfig', () {
    test('encode/decode round-trips all fields', () {
      const cfg = PrinterConfig(
        type: PrinterConnectionType.network,
        address: '192.168.1.50:9100',
        name: 'Caja 1',
        paperSize: PaperSize.mm80,
      );
      final back = PrinterConfig.decode(cfg.encode());
      expect(back, isNotNull);
      expect(back!.type, PrinterConnectionType.network);
      expect(back.address, '192.168.1.50:9100');
      expect(back.name, 'Caja 1');
      expect(back.paperSize, PaperSize.mm80);
    });

    test('decode returns null on empty/garbage', () {
      expect(PrinterConfig.decode(null), isNull);
      expect(PrinterConfig.decode(''), isNull);
      expect(PrinterConfig.decode('not json'), isNull);
      expect(PrinterConfig.decode('{"type":"usb"}'), isNull); // no address
    });

    test('networkEndpoint splits host and port, defaults to 9100', () {
      const a = PrinterConfig(
          type: PrinterConnectionType.network,
          address: '10.0.0.9:9100',
          name: '');
      expect(a.networkEndpoint.host, '10.0.0.9');
      expect(a.networkEndpoint.port, 9100);

      const b = PrinterConfig(
          type: PrinterConnectionType.network, address: '10.0.0.9', name: '');
      expect(b.networkEndpoint.host, '10.0.0.9');
      expect(b.networkEndpoint.port, kDefaultPrinterPort);
    });

    test('connection type predicates', () {
      const bt = PrinterConfig(
          type: PrinterConnectionType.bluetooth, address: 'X', name: '');
      const usb =
          PrinterConfig(type: PrinterConnectionType.usb, address: 'X', name: '');
      const net = PrinterConfig(
          type: PrinterConnectionType.network, address: 'X', name: '');
      expect(bt.isBluetooth, isTrue);
      expect(usb.isUsb, isTrue);
      expect(net.isNetwork, isTrue);
    });

    test('default paper size is mm80 (the DIG-E200I width)', () {
      const cfg = PrinterConfig(
          type: PrinterConnectionType.usb, address: 'X', name: '');
      expect(cfg.paperSize, PaperSize.mm80);
    });
  });
}
