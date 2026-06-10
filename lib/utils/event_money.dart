// Spec: specs/042-modulo-eventos/spec.md
//
// Formateo de dinero de eventos con moneda (COP / USD). COP usa separador de
// miles con puntos ("$1.550.000"); USD usa coma ("US$1,550"). El precio se
// guarda como entero en la unidad de la moneda.

import 'package:intl/intl.dart';

/// Monedas soportadas por un evento de pago.
class EventCurrency {
  static const cop = 'COP';
  static const usd = 'USD';

  static const all = [cop, usd];

  /// Etiqueta corta para selectores ("Peso COP" / "Dólar USD").
  static String label(String v) => switch (v) {
        usd => 'Dólar (USD)',
        _ => 'Peso (COP)',
      };

  /// Normaliza un valor posiblemente nulo/vacío a COP por defecto.
  static String normalize(String? v) => v == usd ? usd : cop;
}

final NumberFormat _copFmt = NumberFormat('#,##0', 'es_CO');
final NumberFormat _usdFmt = NumberFormat('#,##0', 'en_US');

/// Formatea un monto entero en su moneda: "$1.550.000" (COP) o "US$1,550" (USD).
String formatEventMoney(int amount, String currency) {
  if (EventCurrency.normalize(currency) == EventCurrency.usd) {
    return 'US\$${_usdFmt.format(amount)}';
  }
  return '\$${_copFmt.format(amount)}';
}

/// Como [formatEventMoney] pero muestra "Gratis" cuando el monto es 0.
String formatEventPrice(int amount, String currency) =>
    amount <= 0 ? 'Gratis' : formatEventMoney(amount, currency);
