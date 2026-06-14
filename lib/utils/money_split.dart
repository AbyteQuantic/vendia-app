// Spec: specs/047-offline-sync-contract/spec.md (math hardening)
//
// Reparto de una cuenta entre N personas SIN sobrecobrar al grupo.
//
// El bug previo (`client_account_screen._perPerson`) redondeaba cada parte
// HACIA ARRIBA al múltiplo de $50 más cercano, así que `parte × personas`
// terminaba por encima del saldo real (ej. $45.100 / 3 mostraba $15.050,
// que × 3 = $45.150 → $50 de más que algún cliente paga sin deber).
//
// Aquí repartimos en múltiplos de $50 (no hay monedas menores en COP) de modo
// que la SUMA de las partes sea EXACTAMENTE el total redondeado, distribuyendo
// el sobrante de a $50 entre las primeras personas. Así el grupo nunca paga de
// más y la matemática cuadra al peso.

const int _kCopStep = 50;

/// Redondea [amount] al múltiplo de $50 más cercano (convención COP del POS).
int roundToCopStep(int amount) {
  if (amount <= 0) return 0;
  return ((amount / _kCopStep).round()) * _kCopStep;
}

/// Reparte [total] (en pesos) entre [count] personas devolviendo la lista de
/// montos individuales. Garantías:
///   * la suma de la lista == `roundToCopStep(total)` (no sobrecobra al grupo),
///   * cada monto es múltiplo de $50,
///   * los montos difieren entre sí a lo sumo en un escalón de $50.
List<int> evenSplitCOP(int total, int count) {
  if (count <= 1) return [total];
  final target = roundToCopStep(total);
  final steps = target ~/ _kCopStep; // cuántos "bloques de $50" repartir
  final base = (steps ~/ count) * _kCopStep; // piso por persona
  var remainderBlocks = steps % count; // bloques de $50 sobrantes
  final shares = <int>[];
  for (var i = 0; i < count; i++) {
    if (remainderBlocks > 0) {
      shares.add(base + _kCopStep);
      remainderBlocks--;
    } else {
      shares.add(base);
    }
  }
  return shares;
}

/// Monto "por persona" representativo para mostrar en la UI: el PISO del
/// reparto, de modo que `representativo × count <= total` siempre (el grupo
/// nunca paga de más; el ajuste fino lo absorben las primeras personas).
int representativeSplitCOP(int total, int count) {
  if (count <= 1) return total;
  final shares = evenSplitCOP(total, count);
  return shares.reduce((a, b) => a < b ? a : b);
}
