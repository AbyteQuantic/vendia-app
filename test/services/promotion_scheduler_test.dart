// Spec: specs/033-difusion-promociones/spec.md
//
// Test del helper de programación de envío de promociones (F033 —
// AC-06d). Cubre la función pura `resolveSchedule`.

import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/promotion_scheduler.dart';

void main() {
  group('resolveSchedule', () {
    test('"ahora" devuelve null (envío inmediato)', () {
      expect(resolveSchedule(PromotionSchedule.now), isNull);
    });

    test('"mañana 9am" cae al día siguiente a las 9:00', () {
      // Miércoles 2026-05-20 14:30.
      final from = DateTime(2026, 5, 20, 14, 30);
      final result =
          resolveSchedule(PromotionSchedule.tomorrow9am, from: from);
      expect(result, DateTime(2026, 5, 21, 9));
    });

    test('"viernes 6pm" desde un miércoles cae al viernes de esa semana',
        () {
      // Miércoles 2026-05-20.
      final from = DateTime(2026, 5, 20, 10);
      final result =
          resolveSchedule(PromotionSchedule.nextFriday6pm, from: from);
      expect(result, DateTime(2026, 5, 22, 18));
    });

    test('"viernes 6pm" desde un viernes salta al viernes siguiente', () {
      // Viernes 2026-05-22.
      final from = DateTime(2026, 5, 22, 10);
      final result =
          resolveSchedule(PromotionSchedule.nextFriday6pm, from: from);
      expect(result, DateTime(2026, 5, 29, 18));
    });

    test('"viernes 6pm" desde un sábado cae al viernes de la próxima semana',
        () {
      // Sábado 2026-05-23.
      final from = DateTime(2026, 5, 23, 10);
      final result =
          resolveSchedule(PromotionSchedule.nextFriday6pm, from: from);
      expect(result, DateTime(2026, 5, 29, 18));
    });
  });
}
