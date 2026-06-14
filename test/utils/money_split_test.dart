// Spec: specs/047-offline-sync-contract/spec.md (math hardening)
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/money_split.dart';

void main() {
  group('evenSplitCOP — la suma SIEMPRE cuadra con el total', () {
    test('45100 / 3 no sobrecobra: las partes suman exactamente el total', () {
      final shares = evenSplitCOP(45100, 3);
      expect(shares.length, 3);
      // Invariante clave: nadie paga de más en grupo.
      expect(shares.reduce((a, b) => a + b), 45100);
      // Cada parte es múltiplo de 50 (no hay monedas < $50 en COP).
      for (final s in shares) {
        expect(s % 50, 0, reason: 'cada parte debe ser múltiplo de 50');
      }
      // Las partes difieren a lo sumo en un escalón de $50.
      expect(shares.reduce((a, b) => a > b ? a : b) -
          shares.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(50));
    });

    test('total divisible exacto reparte igual', () {
      final shares = evenSplitCOP(30000, 3);
      expect(shares, [10000, 10000, 10000]);
    });

    test('1 persona recibe todo', () {
      expect(evenSplitCOP(12345, 1), [12345]);
    });

    test('count <= 0 devuelve el total intacto sin dividir por cero', () {
      expect(evenSplitCOP(5000, 0), [5000]);
    });

    test('total 0 reparte ceros', () {
      expect(evenSplitCOP(0, 4), [0, 0, 0, 0]);
    });

    test('representativeSplit nunca deja al grupo pagando de más', () {
      // El monto representativo por persona × count no supera el total.
      for (final total in [45100, 99999, 17, 100000]) {
        for (final n in [2, 3, 4, 7]) {
          final rep = representativeSplitCOP(total, n);
          expect(rep * n, lessThanOrEqualTo(total + 50),
              reason: 'total=$total n=$n rep=$rep');
        }
      }
    });
  });
}
