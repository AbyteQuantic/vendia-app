// Spec: specs/100-completar-skus-inventario/spec.md (T-11, D2)
//
// Generador de SKU interno — extraído de create_product_screen.dart y
// manage_inventory_screen.dart (estaba duplicado en ambos, Art. IX).
// Formato histórico intacto: VND-<PRES3>-<AAA>-<4 dígitos>.
//
// Cambio deliberado (plan D2): el sufijo usa `Random.secure()` en vez de
// `millisecondsSinceEpoch % 10000` — en ráfaga (varios "Generar" en el
// mismo milisegundo) la semilla por reloj producía sufijos idénticos o
// casi-consecutivos, es decir MÁS colisiones justo cuando más se genera.

import 'dart:math';

final Random _secureRandom = Random.secure();

/// Prefijos de presentación (3 letras). Unión de los dos mapas que existían
/// (el de crear producto y el de editar producto); lookup case-insensitive
/// para cubrir ambas variantes históricas ('Botella' y 'botella').
const Map<String, String> _presentationPrefixes = {
  'botella': 'BOT',
  'lata': 'LAT',
  'bolsa': 'BLS',
  'caja': 'CAJ',
  'frasco': 'FRA',
  'paquete': 'PAQ',
  'unidad': 'UNI',
  'sobre': 'SOB',
  'otro': 'OTR',
};

/// Genera un SKU interno `VND-<PRES>-<AAA>-<dddd>` a partir del nombre y la
/// presentación del producto. Ej.: `VND-UNI-EMP-4821` para "Empanada" /
/// "Unidad". [random] es inyectable solo para pruebas.
String generateSku({
  required String name,
  required String presentation,
  Random? random,
}) {
  final pres =
      _presentationPrefixes[presentation.trim().toLowerCase()] ?? 'GEN';
  final letters =
      name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  final nameCode = letters.length >= 3
      ? letters.substring(0, 3)
      : letters.padRight(3, 'X');
  final digits =
      (random ?? _secureRandom).nextInt(10000).toString().padLeft(4, '0');
  return 'VND-$pres-$nameCode-$digits';
}
