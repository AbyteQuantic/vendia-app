import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/promotions/promo_builder_screen.dart';

/// Garantiza que la nueva lógica "Tendero-Speak" distribuye el precio
/// total del combo (único input global) de forma proporcional al peso
/// de cada línea, y que la suma siempre cuadra exactamente — el
/// backend no debería ver nunca un cent de redondeo perdido.
void main() {
  int totalOf(List<ComboLineDistribution> r) =>
      r.fold(0, (s, d) => s + d.promoPriceEach * d.quantity);

  group('distributeComboTotal', () {
    test('reparto proporcional 2 productos — exacto', () {
      final r = distributeComboTotal(
        lines: const [
          ComboLineInput(
              productId: 'pan', unitPrice: 3000, quantity: 1),
          ComboLineInput(
              productId: 'leche', unitPrice: 6000, quantity: 1),
        ],
        totalComboPrice: 7500, // descuento de $1500 sobre $9000 normal
      );
      expect(r.length, 2);
      // Peso 1/3 y 2/3 → 2500 / 5000
      expect(r[0].promoPriceEach, 2500);
      expect(r[1].promoPriceEach, 5000);
      expect(totalOf(r), 7500);
    });

    test('varias unidades — respeta price*qty como peso', () {
      final r = distributeComboTotal(
        lines: const [
          ComboLineInput(
              productId: 'galleta', unitPrice: 1000, quantity: 3),
          ComboLineInput(
              productId: 'gaseosa', unitPrice: 5000, quantity: 1),
        ],
        totalComboPrice: 6400, // $1600 de descuento sobre $8000
      );
      // Peso gal = 3000/8000 = 0.375 → lineTotal 2400 → 800 c/u
      // Peso gas = 5000/8000 = 0.625 → último absorbe resto
      expect(r[0].promoPriceEach, 800);
      // 6400 - 2400 = 4000 en la gaseosa
      expect(r[1].promoPriceEach, 4000);
      expect(totalOf(r), 6400);
    });

    test('suma siempre cuadra aun con residuo de redondeo', () {
      final r = distributeComboTotal(
        lines: const [
          ComboLineInput(productId: 'a', unitPrice: 333, quantity: 1),
          ComboLineInput(productId: 'b', unitPrice: 333, quantity: 1),
          ComboLineInput(productId: 'c', unitPrice: 333, quantity: 1),
        ],
        totalComboPrice: 1000,
      );
      // 3 líneas iguales, total 1000 → residuo de redondeo lo absorbe
      // la última. Lo crítico es que el total cuadra.
      expect(totalOf(r), 1000);
    });

    test('todos los precios en 0 → reparte por unidades', () {
      final r = distributeComboTotal(
        lines: const [
          ComboLineInput(productId: 'a', unitPrice: 0, quantity: 2),
          ComboLineInput(productId: 'b', unitPrice: 0, quantity: 2),
        ],
        totalComboPrice: 4000,
      );
      // 4 unidades → 1000 c/u
      expect(r[0].promoPriceEach, 1000);
      expect(r[1].promoPriceEach, 1000);
      expect(totalOf(r), 4000);
    });

    test('total 0 → todo queda en 0 sin crashear', () {
      final r = distributeComboTotal(
        lines: const [
          ComboLineInput(productId: 'a', unitPrice: 5000, quantity: 1),
        ],
        totalComboPrice: 0,
      );
      expect(r.single.promoPriceEach, 0);
    });

    test('total negativo se sanea a 0', () {
      final r = distributeComboTotal(
        lines: const [
          ComboLineInput(productId: 'a', unitPrice: 1000, quantity: 1),
        ],
        totalComboPrice: -500,
      );
      expect(r.single.promoPriceEach, 0);
    });

    test('lista vacía → lista vacía', () {
      expect(
        distributeComboTotal(lines: const [], totalComboPrice: 1000),
        isEmpty,
      );
    });
  });
}
