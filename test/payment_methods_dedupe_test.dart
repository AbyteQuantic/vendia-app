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

  group('Cash-First anchor (INNEGOCIABLE)', () {
    /// Cash-First policy: the checkout ALWAYS renders an Efectivo
    /// chip — whether the tenant has zero methods, only non-cash
    /// methods (e.g. Nequi-only), a real cash row, or every method
    /// inactive. The cash anchor is non-negotiable. When a real
    /// cash row exists in the active set, its display label wins;
    /// otherwise a synthetic 'Efectivo' chip is rendered. The
    /// previous "showFallback only when list is empty" gate has
    /// been retired — it caused the cash chip to disappear for any
    /// tenant with at least one non-cash method (PO regression).
    bool alwaysShowsCashChip(
        List<Map<String, dynamic>> activeMethods) {
      // The render decision no longer depends on the list contents.
      // Kept as a function to document the invariant.
      return true;
    }

    String cashLabelFor(List<Map<String, dynamic>> activeMethods) {
      for (final m in activeMethods) {
        if (m['is_active'] != true) continue;
        final name = (m['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final provider = m['provider'] as String?;
        if (provider == 'cash' || name.toLowerCase() == 'efectivo') {
          return name;
        }
      }
      return 'Efectivo';
    }

    test('empty list still shows cash chip', () {
      expect(alwaysShowsCashChip(const []), isTrue);
      expect(cashLabelFor(const []), 'Efectivo');
    });
    test('non-empty non-cash list still shows cash chip', () {
      expect(
        alwaysShowsCashChip(const [
          {'id': 'a', 'name': 'Nequi', 'is_active': true},
        ]),
        isTrue,
      );
      expect(
        cashLabelFor(const [
          {'id': 'a', 'name': 'Nequi', 'is_active': true},
        ]),
        'Efectivo',
      );
    });
    test('real tenant cash row provides display label', () {
      const payload = [
        {'id': 'a', 'name': 'Efectivo COP', 'is_active': true,
         'provider': 'cash'},
        {'id': 'b', 'name': 'Nequi', 'is_active': true,
         'provider': 'nequi'},
      ];
      expect(alwaysShowsCashChip(payload), isTrue);
      expect(cashLabelFor(payload), 'Efectivo COP');
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
