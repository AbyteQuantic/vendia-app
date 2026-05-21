// Spec: specs/029-precios-multi-tier/spec.md
//
// T-26 — cart_controller tests para el selector de tier.
// Cobertura:
//   - setPriceTier('tier_2') recalcula el total usando price_tier_2.
//   - Item sin price_tier_2 cae al retail (fallback) en el total y queda
//     marcado vía itemUsingRetailFallback.
//   - setPriceTier('retail') restituye el cálculo legacy.
//   - tier no reconocido → no-op.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/models/product.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Fixtures ──────────────────────────────────────────────────────────────
  //
  // El depósito típico de F029: dos productos en el carrito.
  //   - Cemento → tier_1 25_000, tier_2 26_500, tier_3 28_500, retail 28_500.
  //   - Tornillo → solo tiene retail (1_000) — los tiers son null.
  Product cemento() => const Product(
        id: 1,
        uuid: 'p-cemento',
        name: 'Cemento Fortecem',
        price: 28500,
        stock: 100,
        priceTier1: 25000,
        priceTier2: 26500,
        priceTier3: 28500,
      );

  Product tornillo() => const Product(
        id: 2,
        uuid: 'p-tornillo',
        name: 'Tornillo 1/4',
        price: 1000,
        stock: 500,
        // Sin price_tier_* → debe disparar fallback retail con aviso.
      );

  group('CartController · setPriceTier (F029)', () {
    test('default selectedPriceTier es "retail"', () {
      final ctrl = CartController();
      expect(ctrl.selectedPriceTier, 'retail');
    });

    test(
        'setPriceTier("tier_2") recalcula el total usando price_tier_2 '
        'cuando el producto lo tiene', () {
      final ctrl = CartController();
      // 10 sacos de cemento.
      final p = cemento();
      for (var i = 0; i < 10; i++) {
        ctrl.addProduct(p);
      }
      // Retail: 10 * 28_500 = 285_000.
      expect(ctrl.activeTotal, closeTo(285000, 0.01));

      ctrl.setPriceTier('tier_2');
      // tier_2: 10 * 26_500 = 265_000.
      expect(ctrl.selectedPriceTier, 'tier_2');
      expect(ctrl.activeTotal, closeTo(265000, 0.01));
    });

    test(
        'item sin price_tier_N cae al retail (fallback) en el total — '
        'pero el resto del carrito sí usa el tier', () {
      final ctrl = CartController();
      ctrl.addProduct(cemento()); // tier_1 = 25_000
      ctrl.addProduct(tornillo()); // sin tier_1 → fallback retail 1_000

      ctrl.setPriceTier('tier_1');
      // 25_000 (cemento tier_1) + 1_000 (tornillo retail fallback) = 26_000
      expect(ctrl.activeTotal, closeTo(26000, 0.01));
    });

    test('itemUsingRetailFallback marca solo los items sin ese tier', () {
      final ctrl = CartController();
      ctrl.addProduct(cemento());
      ctrl.addProduct(tornillo());
      ctrl.setPriceTier('tier_3');

      final items = ctrl.activeCart;
      // Cemento tiene tier_3 → no usa fallback.
      expect(ctrl.itemUsingRetailFallback(items[0]), isFalse);
      // Tornillo no tiene ningún tier → usa fallback.
      expect(ctrl.itemUsingRetailFallback(items[1]), isTrue);
    });

    test('retail nunca dispara fallback aunque tier_N sea null', () {
      final ctrl = CartController();
      ctrl.addProduct(tornillo());
      ctrl.setPriceTier('retail');
      expect(ctrl.itemUsingRetailFallback(ctrl.activeCart.first), isFalse);
    });

    test(
        'volver a "retail" tras un tier restituye el total legacy '
        '(invariante AC-07)', () {
      final ctrl = CartController();
      ctrl.addProduct(cemento());
      ctrl.addProduct(cemento());
      final retailTotal = ctrl.activeTotal;

      ctrl.setPriceTier('tier_2');
      expect(ctrl.activeTotal, isNot(closeTo(retailTotal, 0.01)));

      ctrl.setPriceTier('retail');
      expect(ctrl.activeTotal, closeTo(retailTotal, 0.01));
    });

    test('tier no reconocido es ignorado (defensive — no cambia el estado)',
        () {
      final ctrl = CartController();
      ctrl.addProduct(cemento());
      ctrl.setPriceTier('tier_2');
      final beforeTotal = ctrl.activeTotal;

      ctrl.setPriceTier('tier_42');
      expect(ctrl.selectedPriceTier, 'tier_2');
      expect(ctrl.activeTotal, closeTo(beforeTotal, 0.01));
    });

    test('totalForTier hace cálculo sin cambiar el estado activo', () {
      final ctrl = CartController();
      ctrl.addProduct(cemento());
      ctrl.addProduct(cemento());

      expect(ctrl.totalForTier('tier_1'), closeTo(50000, 0.01));
      expect(ctrl.totalForTier('retail'), closeTo(57000, 0.01));
      // El tier activo permaneció en 'retail'.
      expect(ctrl.selectedPriceTier, 'retail');
    });

    test('notifyListeners se dispara solo cuando el tier cambia de verdad',
        () {
      final ctrl = CartController();
      int notifyCount = 0;
      ctrl.addListener(() => notifyCount++);

      ctrl.setPriceTier('tier_1');
      ctrl.setPriceTier('tier_1'); // sin cambio → no notifica
      ctrl.setPriceTier('xxx'); // inválido → no notifica
      ctrl.setPriceTier('tier_2');

      expect(notifyCount, 2);
    });
  });
}
