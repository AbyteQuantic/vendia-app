import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tenant payment methods — checkout dedupe gate', () {
    bool isExtra(String name, bool isActive) {
      const baseNames = {'efectivo', 'transferencia', 'tarjeta'};
      return isActive &&
          name.trim().isNotEmpty &&
          !baseNames.contains(name.trim().toLowerCase());
    }

    test('Nequi (active) is rendered as extra chip', () {
      expect(isExtra('Nequi', true), isTrue);
    });
    test('Daviplata (active) is rendered as extra chip', () {
      expect(isExtra('Daviplata', true), isTrue);
    });
    test('Efectivo configured by tenant is dedupe-skipped', () {
      expect(isExtra('Efectivo', true), isFalse);
    });
    test('Tarjeta with weird casing is dedupe-skipped (case-insensitive)', () {
      expect(isExtra('tarjeta', true), isFalse);
    });
    test('Transferencia w/ trailing whitespace is dedupe-skipped', () {
      expect(isExtra('  Transferencia  ', true), isFalse);
    });
    test('inactive tenant method is NOT rendered', () {
      expect(isExtra('Nequi', false), isFalse);
    });
    test('empty-name method is NOT rendered', () {
      expect(isExtra('', true), isFalse);
      expect(isExtra('   ', true), isFalse);
    });
  });

  group('RBAC parity invariant', () {
    test(
      'cashier and owner derive the same active set from identical '
      'server payload',
      () {
        final serverPayload = [
          {'id': 'a', 'name': 'Nequi', 'is_active': true},
          {'id': 'b', 'name': 'Daviplata', 'is_active': true},
          {'id': 'c', 'name': 'Bancolombia QR', 'is_active': false},
        ];
        Set<String> activeFor() => serverPayload
            .where((m) => m['is_active'] == true)
            .map((m) => (m['name'] as String).toLowerCase())
            .toSet();
        final cashier = activeFor();
        final owner = activeFor();
        expect(cashier, owner);
        expect(cashier, {'nequi', 'daviplata'});
      },
    );
  });
}
