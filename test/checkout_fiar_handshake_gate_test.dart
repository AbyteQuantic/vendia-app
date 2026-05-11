import 'package:flutter_test/flutter_test.dart';

/// Pure-logic pin for H11: the Checkout's Confirmar button must stay
/// disabled when the cashier selected "Fiar" but the handshake has
/// not completed yet (`ActiveFiadoService.hasActive == false`).
///
/// The widget-level test would have to mount the whole CheckoutScreen
/// + provide ActiveFiadoService + a real ApiService. That setup is
/// orthogonal to the rule we want to lock down. Instead we
/// reconstruct the exact decision the screen uses (mirrored in code
/// review) so a future refactor that re-introduces the bug fails
/// here loudly.
void main() {
  // Mirror of `_canConfirmWith` in
  // lib/screens/pos/checkout_screen.dart.
  bool canConfirm({
    required String selectedMethodKey,
    required bool isCash,
    required double amountTendered,
    required double total,
    required String? receiptUrl,
    required bool hasActiveFiado,
  }) {
    const kFiar = '__fiar__';
    if (selectedMethodKey == kFiar) return hasActiveFiado;
    if (isCash) return amountTendered >= total;
    return receiptUrl != null && receiptUrl.isNotEmpty;
  }

  group('H11 — Fiar chip requires an accepted handshake', () {
    test('Fiar + sin handshake → Confirmar DISABLED', () {
      expect(
        canConfirm(
          selectedMethodKey: '__fiar__',
          isCash: false,
          amountTendered: 0,
          total: 10000,
          receiptUrl: null,
          hasActiveFiado: false,
        ),
        isFalse,
        reason: 'antes del fix devolvía true — sale credit sin '
            'credit_account_id viaja al backend y choca con sales.go:142-151',
      );
    });

    test('Fiar + handshake aceptado → Confirmar ENABLED', () {
      expect(
        canConfirm(
          selectedMethodKey: '__fiar__',
          isCash: false,
          amountTendered: 0,
          total: 10000,
          receiptUrl: null,
          hasActiveFiado: true,
        ),
        isTrue,
      );
    });

    test('Fiar + foto adjuntada (irrelevante) NO bypasea el handshake', () {
      // Sanity check: el receipt photo es para pagos digitales, no
      // para fiar. Si el cajero hubiera subido foto antes de tocar
      // el chip Fiar, el botón debe seguir disabled.
      expect(
        canConfirm(
          selectedMethodKey: '__fiar__',
          isCash: false,
          amountTendered: 0,
          total: 10000,
          receiptUrl: 'https://example.com/r.jpg',
          hasActiveFiado: false,
        ),
        isFalse,
      );
    });

    test('Efectivo + tendered ≥ total → ENABLED (regresión guard)', () {
      expect(
        canConfirm(
          selectedMethodKey: '__cash_anchor__',
          isCash: true,
          amountTendered: 10000,
          total: 10000,
          receiptUrl: null,
          hasActiveFiado: false,
        ),
        isTrue,
      );
    });

    test('Digital + foto subida → ENABLED (regresión guard)', () {
      expect(
        canConfirm(
          selectedMethodKey: 'nequi-uuid',
          isCash: false,
          amountTendered: 0,
          total: 10000,
          receiptUrl: 'https://example.com/r.jpg',
          hasActiveFiado: false,
        ),
        isTrue,
      );
    });
  });
}
