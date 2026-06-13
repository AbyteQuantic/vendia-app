// Spec: specs/045-onboarding-agentic/onboarding_agentic_spec.md
//
// Fase 1 — predicados de validación re-alojados, getter canRegister y
// applyParseResult (merge parcial por setters), sin tocar el contrato de
// submit (_buildPayload, employees:[]).
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';

OnboardingStepperController _make() => OnboardingStepperController(
      apiCall: (_) async => {},
      saveSession: (_) async {},
    );

/// Llena todos los requeridos a mano para aislar el campo bajo prueba.
void _fillAllValid(OnboardingStepperController c) {
  c.ownerName = 'María';
  c.ownerLastName = 'Gómez';
  c.phone = '3001234567';
  c.pin = '1234';
  c.confirmPin = '1234';
  c.businessName = 'Tienda Doña Marta';
  c.address = 'Calle 5 #3-20';
  c.setPrimaryBusinessType('tienda_barrio');
  c.setLogoUrl('https://r2/logo.png');
}

void main() {
  group('canRegister + predicados (Fase 1)', () {
    test('arranca en false y pasa a true con todos los requeridos', () {
      final c = _make();
      expect(c.canRegister, isFalse);
      _fillAllValid(c);
      expect(c.canRegister, isTrue);
    });

    test('address es REQUERIDA (aprobado por el fundador)', () {
      final c = _make();
      _fillAllValid(c);
      c.address = '   ';
      expect(c.addressValid, isFalse);
      expect(c.canRegister, isFalse);
    });

    test('logo requerido: sin logoUrl no se puede registrar', () {
      final c = _make();
      _fillAllValid(c);
      c.clearLogo();
      expect(c.canRegister, isFalse);
    });

    test('PIN: 4-8 dígitos y confirmación', () {
      final c = _make();
      _fillAllValid(c);
      c.pin = '12';
      expect(c.pinValid, isFalse);
      c.pin = '123456789';
      expect(c.pinValid, isFalse);
      c.pin = '1234';
      c.confirmPin = '9999';
      expect(c.pinConfirmed, isFalse);
      expect(c.canRegister, isFalse);
      c.confirmPin = '1234';
      expect(c.pinConfirmed, isTrue);
    });

    test('phone requiere al menos 7 dígitos', () {
      final c = _make();
      _fillAllValid(c);
      c.phone = '300';
      expect(c.phoneValid, isFalse);
      c.phone = '300 123 4567';
      expect(c.phoneValid, isTrue);
    });

    test('businessType seleccionado es requerido', () {
      final c = _make();
      _fillAllValid(c);
      c.businessTypes = [];
      expect(c.businessTypeSelected, isFalse);
      expect(c.canRegister, isFalse);
    });
  });

  group('applyParseResult — merge parcial por setters (Fase 1)', () {
    test('escribe los campos detectados por setter; food activa hasTables', () {
      final c = _make();
      c.applyParseResult({
        'fields': {
          'owner_name': 'María',
          'owner_last_name': 'Gómez',
          'phone': '300 123 4567',
          'business_name': 'Doña Marta',
          'address': 'Calle 5 #3-20',
          'business_type': 'comidas_rapidas',
          'has_multiple_branches': true,
        },
        'needs_confirmation': <String>[],
      });
      expect(c.ownerName, 'María');
      expect(c.ownerLastName, 'Gómez');
      expect(c.phone, '3001234567'); // normalizado a dígitos
      expect(c.businessName, 'Doña Marta');
      expect(c.address, 'Calle 5 #3-20');
      expect(c.businessType, 'comidas_rapidas');
      expect(c.hasTables, isTrue); // side-effect de setPrimaryBusinessType (food)
      expect(c.hasMultipleBranches, isTrue);
    });

    test('NO escribe campos en needs_confirmation', () {
      final c = _make();
      c.applyParseResult({
        'fields': {'business_type': 'bar', 'nit': '900123'},
        'needs_confirmation': ['business_type'],
      });
      expect(c.businessType, ''); // baja confianza → no se autollena
      expect(c.nit, '900123'); // este sí (no está en needs_confirmation)
    });

    test('IGNORA el PIN aunque venga en fields (dato sensible, D10)', () {
      final c = _make();
      c.applyParseResult({
        'fields': {'pin': '4321', 'owner_name': 'Ana'},
      });
      expect(c.pin, ''); // jamás escrito por la IA
      expect(c.ownerName, 'Ana');
    });

    test('logo_intent NO escribe logoUrl; solo expone la sugerencia (D11)', () {
      final c = _make();
      c.applyParseResult({
        'fields': {'logo_intent': 'generar'},
      });
      expect(c.logoUrl, ''); // nunca escrito directo
      expect(c.suggestedLogoIntent, 'generar');
    });

    test('merge parcial: null no pisa lo ya escrito a mano', () {
      final c = _make();
      c.businessName = 'Mi Tienda';
      c.applyParseResult({
        'fields': {'business_name': null, 'address': 'Calle 1'},
      });
      expect(c.businessName, 'Mi Tienda'); // preservado
      expect(c.address, 'Calle 1');
    });

    test('business_type fuera de la whitelist se ignora (defensa, D9)', () {
      final c = _make();
      c.applyParseResult({
        'fields': {'business_type': 'algo_invalido'},
      });
      expect(c.businessType, '');
    });

    test('notifica una sola vez por llamada (INV-4)', () {
      final c = _make();
      var calls = 0;
      c.addListener(() => calls++);
      c.applyParseResult({
        'fields': {
          'owner_name': 'María',
          'business_type': 'tienda_barrio',
          'has_multiple_branches': true,
        },
      });
      expect(calls, 1);
    });
  });

  group('contrato de submit intacto (invariantes)', () {
    test('payload conserva employees:[] y constantes', () async {
      Map<String, dynamic>? sent;
      final c = OnboardingStepperController(
        apiCall: (p) async {
          sent = p;
          return {};
        },
        saveSession: (_) async {},
      );
      _fillAllValid(c);
      await c.submit();
      expect(sent!['employees'], isEmpty);
      expect((sent!['config'] as Map)['sale_types'], ['products']);
      expect((sent!['config'] as Map)['has_showcases'], false);
      expect((sent!['owner'] as Map)['name'], 'María Gómez');
      expect((sent!['owner'] as Map)['password'], '1234');
    });
  });
}
