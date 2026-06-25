// Spec: specs/078 — atajos de cantidad de insumos (conversiones CO).
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/quantity_presets.dart';

void main() {
  group('quantityPresetsForUnit — conversiones CO', () {
    test('gramos: 1 libra = 500 g, ½ libra = 250 g', () {
      final p = quantityPresetsForUnit('g');
      expect(p.firstWhere((x) => x.label == '1 libra').amount, 500);
      expect(p.firstWhere((x) => x.label == '½ libra').amount, 250);
      expect(p.firstWhere((x) => x.label == '1 kg').amount, 1000);
    });

    test('kg: 1 libra = 0.5 kg, 1 arroba = 12.5 kg', () {
      final p = quantityPresetsForUnit('kg');
      expect(p.firstWhere((x) => x.label == '1 libra').amount, 0.5);
      expect(p.firstWhere((x) => x.label == '1 arroba').amount, 12.5);
    });

    test('ml: taza 250, vaso 200, litro 1000', () {
      final p = quantityPresetsForUnit('ml');
      expect(p.firstWhere((x) => x.label == '1 taza').amount, 250);
      expect(p.firstWhere((x) => x.label == '1 vaso').amount, 200);
      expect(p.firstWhere((x) => x.label == '1 litro').amount, 1000);
    });

    test('unidad: atajos de conteo (docena = 12)', () {
      final p = quantityPresetsForUnit('unidad');
      expect(p.firstWhere((x) => x.label == 'docena').amount, 12);
      expect(p.firstWhere((x) => x.label == 'media docena').amount, 6);
    });

    test('unidad desconocida → sin atajos (no rompe)', () {
      expect(quantityPresetsForUnit('xyz'), isEmpty);
    });
  });

  group('quantityStepForUnit — paso sensato', () {
    test('gramos paso 50 (no ±1)', () => expect(quantityStepForUnit('g'), 50));
    test('kg paso 0.25', () => expect(quantityStepForUnit('kg'), 0.25));
    test('ml paso 50', () => expect(quantityStepForUnit('ml'), 50));
    test('unidad paso 1', () => expect(quantityStepForUnit('unidad'), 1));
    test('desconocida paso 1', () => expect(quantityStepForUnit('xyz'), 1));
  });
}
