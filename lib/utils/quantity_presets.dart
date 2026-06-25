// Spec: specs/078-centro-tareas-unificado/spec.md
//
// Ayudas de cantidad para insumos de receta. El insumo se costea en su UNIDAD
// BASE (g, kg, ml, l, unidad) — pero el tendero piensa en medidas caseras
// colombianas ("media libra", "una taza", "3 dientes"). Estas funciones puras
// convierten esas medidas a la unidad base para que NO tenga que calcular.
//
// REGLA DE ORO: NO tocan el costeo (Σ insumo·cantidad). Solo facilitan escribir
// la cantidad. Lógica pura (sin Flutter) → unit-testeable.
//
// Equivalencias Colombia: 1 libra = 500 g · 1 arroba = 12.5 kg ·
// 1 taza ≈ 250 ml · 1 vaso ≈ 200 ml.

class QuantityPreset {
  final String label; // "1 libra"
  final double amount; // cantidad YA convertida a la unidad base del insumo
  const QuantityPreset(this.label, this.amount);
}

/// Atajos rápidos según la unidad base del insumo. Cada uno SUMA su [amount]
/// a la cantidad actual (igual que el +/-). Lista vacía para unidades raras.
List<QuantityPreset> quantityPresetsForUnit(String unit) {
  switch (unit) {
    case 'g':
      return const [
        QuantityPreset('½ libra', 250),
        QuantityPreset('1 libra', 500),
        QuantityPreset('1 kg', 1000),
        QuantityPreset('100 g', 100),
      ];
    case 'kg':
      return const [
        QuantityPreset('1 libra', 0.5),
        QuantityPreset('1 kg', 1),
        QuantityPreset('1 arroba', 12.5),
      ];
    case 'ml':
      return const [
        QuantityPreset('1 vaso', 200),
        QuantityPreset('1 taza', 250),
        QuantityPreset('½ litro', 500),
        QuantityPreset('1 litro', 1000),
      ];
    case 'l':
      return const [
        QuantityPreset('1 taza', 0.25),
        QuantityPreset('½ litro', 0.5),
        QuantityPreset('1 litro', 1),
      ];
    case 'unidad':
      return const [
        QuantityPreset('+1', 1),
        QuantityPreset('+3', 3),
        QuantityPreset('media docena', 6),
        QuantityPreset('docena', 12),
      ];
    default:
      return const [];
  }
}

/// Paso sensato del +/- según la unidad: ±1 gramo es inútil; ±50 g o ±0.25 kg
/// sí. Mantiene el stepper útil sin que el tendero teclee.
double quantityStepForUnit(String unit) {
  switch (unit) {
    case 'g':
      return 50;
    case 'kg':
      return 0.25;
    case 'ml':
      return 50;
    case 'l':
      return 0.25;
    case 'unidad':
    default:
      return 1;
  }
}
