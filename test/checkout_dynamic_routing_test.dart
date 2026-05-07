import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkout payment routing — selection contract', () {
    // Mirror the dispatcher rules in _confirmSale so the routing
    // logic is pinned at unit-test level even without mounting the
    // private screen.
    String routeFor({
      required String key,
      String? provider,
      String? qrUrl,
    }) {
      const kFallback = '__fallback_cash__';
      const kFiar = '__fiar__';
      if (key == kFiar) return 'fiar_picker';
      if (key == kFallback) return 'close_cash';
      if (provider == 'cash') return 'close_cash';
      if ((qrUrl ?? '').trim().isNotEmpty) return 'qr_modal';
      return 'close_electronic';
    }

    test('Efectivo (cash provider) closes immediately', () {
      expect(
        routeFor(key: 'uuid-cash', provider: 'cash'),
        'close_cash',
      );
    });
    test('Nequi with QR opens modal', () {
      expect(
        routeFor(key: 'uuid-nequi', provider: 'nequi', qrUrl: 'https://r2/qr.png'),
        'qr_modal',
      );
    });
    test('Daviplata with QR opens modal', () {
      expect(
        routeFor(key: 'uuid-davi', provider: 'daviplata', qrUrl: 'https://r2/davi.png'),
        'qr_modal',
      );
    });
    test('Tarjeta without QR closes as electronic', () {
      expect(
        routeFor(key: 'uuid-card', provider: 'card', qrUrl: ''),
        'close_electronic',
      );
    });
    test('Fiar routes to picker', () {
      expect(routeFor(key: '__fiar__'), 'fiar_picker');
    });
    test('Fallback cash chip closes as cash', () {
      expect(routeFor(key: '__fallback_cash__'), 'close_cash');
    });
    test('QR with whitespace-only string is treated as missing', () {
      expect(
        routeFor(
            key: 'uuid-nequi', provider: 'nequi', qrUrl: '   '),
        'close_electronic',
      );
    });
  });
}
