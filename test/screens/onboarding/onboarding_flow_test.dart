// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_flow.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';

OnboardingStepperController _c() => OnboardingStepperController(
      apiCall: (_) async => {},
      saveSession: (_) async {},
    );

void main() {
  group('Flujo de preguntas — skip y orden (Fase 2)', () {
    test('arranca en la pregunta del propietario', () {
      final c = _c();
      expect(firstUnansweredIndex(c, {}), 0);
      expect(kOnboardingQuestions[0].id, 'owner');
    });

    test('la IA que llena owner+phone salta a la pregunta de PIN', () {
      final c = _c();
      c.setOwnerName('María');
      c.setOwnerLastName('Gómez');
      c.setPhone('3001234567');
      // owner y phone resueltos por getters → primera no resuelta = pin (2).
      expect(firstUnansweredIndex(c, {}), 2);
      expect(kOnboardingQuestions[2].id, 'pin');
    });

    test('local y empleados requieren respuesta explícita (set answered)', () {
      final c = _c();
      // Todo lo demás resuelto:
      c.setOwnerName('María');
      c.setOwnerLastName('Gómez');
      c.setPhone('3001234567');
      c.setPin('1234');
      c.setConfirmPin('1234');
      c.setBusinessName('Tienda');
      c.setAddress('Calle 5');
      c.setPrimaryBusinessType('tienda_barrio');
      c.setLogoUrl('https://r2/logo.png');
      // Falta 'local' (índice 5) → no resuelto por getter.
      expect(firstUnansweredIndex(c, {}), 5);
      final answered = {'local'};
      // Ahora falta 'empleados' (índice 7).
      expect(firstUnansweredIndex(c, answered), 7);
    });
  });

  group('Undo — reset por setter (Fase 2)', () {
    test('reset de tipo limpia businessTypes vía clearBusinessType', () {
      final c = _c();
      c.setPrimaryBusinessType('bar');
      expect(c.businessTypeSelected, isTrue);
      questionById('tipo').reset(c, {});
      expect(c.businessTypeSelected, isFalse);
    });

    test('re-elegir tipo tras el undo recalcula hasTables (side-effect intacto)',
        () {
      final c = _c();
      c.setPrimaryBusinessType('bar'); // food → hasTables true
      expect(c.hasTables, isTrue);
      questionById('tipo').reset(c, {});
      c.setPrimaryBusinessType('tienda_barrio'); // no food → hasTables false
      expect(c.hasTables, isFalse);
    });

    test('reset de empleados vuelve a sin-responder', () {
      final c = _c();
      final answered = {'empleados'};
      c.setHasEmployees(true);
      questionById('empleados').reset(c, answered);
      expect(c.hasEmployees, isNull);
      expect(answered.contains('empleados'), isFalse);
    });

    test('reset de owner limpia nombre y apellido', () {
      final c = _c();
      c.setOwnerName('María');
      c.setOwnerLastName('Gómez');
      questionById('owner').reset(c, {});
      expect(c.ownerName, '');
      expect(c.ownerLastName, '');
      expect(c.ownerValid, isFalse);
    });
  });
}
