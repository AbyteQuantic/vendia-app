// Spec: specs/033-difusion-promociones/spec.md
//
// Helper de programación de envío de promociones (F033 — spec §4.5
// mejora 5, AC-06d).
//
// El dueño puede elegir cuándo se envía la promo: "ahora", "mañana 9am"
// o "este viernes 6pm" (presets típicos de mejor conversión). Este
// helper traduce cada preset a un `DateTime` concreto que viaja como
// `scheduled_for` en el payload de la promoción; el backend dispara el
// push notification cuando llega la hora.
//
// Funciones puras y testeables — no tocan red ni estado.

/// Opciones de programación de envío de una promoción.
enum PromotionSchedule {
  /// Enviar ahora — `scheduled_for` queda en null.
  now,

  /// Mañana a las 9:00 am.
  tomorrow9am,

  /// El próximo viernes a las 6:00 pm.
  nextFriday6pm;

  /// Etiqueta en español para los botones de selección.
  String get label {
    switch (this) {
      case PromotionSchedule.now:
        return 'Enviar ahora';
      case PromotionSchedule.tomorrow9am:
        return 'Mañana 9 am';
      case PromotionSchedule.nextFriday6pm:
        return 'Viernes 6 pm';
    }
  }
}

/// Resuelve el [PromotionSchedule] a un `DateTime` concreto a partir de
/// la fecha de referencia [from].
///
/// Devuelve null para [PromotionSchedule.now] (envío inmediato).
DateTime? resolveSchedule(PromotionSchedule schedule, {DateTime? from}) {
  final base = from ?? DateTime.now();
  switch (schedule) {
    case PromotionSchedule.now:
      return null;
    case PromotionSchedule.tomorrow9am:
      final tomorrow = base.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
    case PromotionSchedule.nextFriday6pm:
      // DateTime.friday == 5. Buscamos el próximo viernes; si hoy es
      // viernes saltamos al de la semana siguiente para que "viernes"
      // siempre sea a futuro.
      var daysUntilFriday = (DateTime.friday - base.weekday) % 7;
      if (daysUntilFriday == 0) daysUntilFriday = 7;
      final friday = base.add(Duration(days: daysUntilFriday));
      return DateTime(friday.year, friday.month, friday.day, 18);
  }
}
