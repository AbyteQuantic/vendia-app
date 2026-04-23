import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/promotions/promo_builder_screen.dart';

void main() {
  group('BuyXPayYFinancials.compute', () {
    test('3x2 sobre producto a \$5.000 con costo 70%', () {
      // Escenario de tablero: gaseosa 5.000, costo 3.500, Lleva 3, paga 2.
      final f = BuyXPayYFinancials.compute(
        unitPrice: 5000,
        unitCost: 3500,
        buyQty: 3,
        payQty: 2,
      );

      // El cliente se lleva 3 unidades — precio de lista = 15.000.
      expect(f.totalRegular, 15000);
      // Paga sólo 2 — la tienda factura 10.000.
      expect(f.totalPromo, 10000);
      // Costo real de las 3 unidades (el tendero saca 3 del inventario).
      expect(f.cost, 10500);
      // Descuento otorgado: 15.000 - 10.000 = 5.000.
      expect(f.discountAmount, 5000);
      // ~33.3% de descuento efectivo.
      expect(f.discountPercent, closeTo(33.33, 0.1));
      // Utilidad = ingresa 10.000 − cuesta 10.500 = −500 → pérdida.
      expect(f.netProfit, -500);
      expect(f.isProfitable, isFalse);
    });

    test('2x1 sobre producto con margen sano es rentable', () {
      // Producto a 10.000 y costo 4.000 (40% cost factor, buen margen).
      // 2x1 = se lleva 2, paga 1.
      final f = BuyXPayYFinancials.compute(
        unitPrice: 10000,
        unitCost: 4000,
        buyQty: 2,
        payQty: 1,
      );

      expect(f.totalRegular, 20000);
      expect(f.totalPromo, 10000);
      expect(f.cost, 8000);
      expect(f.netProfit, 2000);
      expect(f.isProfitable, isTrue);
      expect(f.discountPercent, 50);
    });

    test('unitPrice = 0 no divide por cero en discountPercent', () {
      final f = BuyXPayYFinancials.compute(
        unitPrice: 0,
        unitCost: 0,
        buyQty: 3,
        payQty: 2,
      );
      expect(f.discountPercent, 0);
      expect(f.totalRegular, 0);
      expect(f.isProfitable, isTrue); // 0 - 0 = 0
    });

    test('payQty = buyQty → no hay descuento (edge case)', () {
      // Aunque la UI previene este estado, verificamos que la
      // matemática no explota.
      final f = BuyXPayYFinancials.compute(
        unitPrice: 5000,
        unitCost: 3500,
        buyQty: 3,
        payQty: 3,
      );
      expect(f.discountAmount, 0);
      expect(f.discountPercent, 0);
      expect(f.netProfit, f.totalPromo - f.cost);
    });
  });
}
