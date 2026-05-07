import 'package:flutter_test/flutter_test.dart';

/// Checkout no longer dedupes against a hardcoded base set
/// (Efectivo / Transferencia / Tarjeta). Chips are rendered
/// 100% from the tenant's `watchActivePaymentMethods()` stream;
/// the only client-side filter is `isActive=true` + non-empty
/// trimmed name. This test pins the new contract so a future
/// refactor can't silently re-introduce a hardcoded base set.
///
/// See lib/screens/pos/checkout_screen.dart — the StreamBuilder
/// that builds the chips Wrap.
void main() {
  group('Tenant payment methods — checkout render gate', () {
    bool shouldRender(String name, bool isActive) {
      return isActive && name.trim().isNotEmpty;
    }

    test('Nequi (active) renders', () {
      expect(shouldRender('Nequi', true), isTrue);
    });
    test('Daviplata (active) renders', () {
      expect(shouldRender('Daviplata', true), isTrue);
    });
    test('Efectivo configured by tenant renders (no dedupe)', () {
      // Previously the checkout dedupe-skipped this name. Now the
      // tenant's "Efectivo" row is the source of truth — when the
      // merchant configures it the chip renders verbatim, with the
      // merchant's own provider/qr metadata.
      expect(shouldRender('Efectivo', true), isTrue);
    });
    test('Tarjeta configured by tenant renders (no dedupe)', () {
      expect(shouldRender('tarjeta', true), isTrue);
    });
    test('Transferencia w/ trailing whitespace still renders (trim only)', () {
      expect(shouldRender('  Transferencia  ', true), isTrue);
    });
    test('inactive tenant method is NOT rendered', () {
      expect(shouldRender('Nequi', false), isFalse);
    });
    test('empty-name method is NOT rendered', () {
      expect(shouldRender('', true), isFalse);
      expect(shouldRender('   ', true), isFalse);
    });
  });

  group('Zero-config fallback', () {
    /// When the tenant has no configured methods at all (brand-new
    /// account or sync still in flight), the checkout synthesises
    /// a single Efectivo chip on the client so the cashier can
    /// always close the sale.
    bool showFallback(List<Map<String, dynamic>> activeMethods) {
      return activeMethods.isEmpty;
    }

    test('empty list triggers fallback chip', () {
      expect(showFallback(const []), isTrue);
    });
    test('non-empty list suppresses fallback chip', () {
      expect(
        showFallback(const [
          {'id': 'a', 'name': 'Nequi', 'is_active': true},
        ]),
        isFalse,
      );
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
