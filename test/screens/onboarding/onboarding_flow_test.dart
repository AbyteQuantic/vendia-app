// Spec: specs/106-onboarding-conversacional-agente/spec.md
//
// Registro corto (T-27): el flujo queda en owner→phone→pin; el payload es
// mínimo (credenciales + términos + aviso de datos, AC-15) y el PostLoginGate
// enruta a VendiChatScreen cuando el onboarding no está completo (AC-01).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_flow.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';
import 'package:vendia_pos/screens/onboarding/post_login_gate.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_screen.dart';

OnboardingStepperController _c({
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? apiCall,
}) =>
    OnboardingStepperController(
      apiCall: apiCall ?? (_) async => {},
      saveSession: (_) async {},
    );

void _fillCredentials(OnboardingStepperController c) {
  c.setOwnerName('María');
  c.setOwnerLastName('Gómez');
  c.setPhone('3001234567');
  c.setPin('1234');
  c.setConfirmPin('1234');
}

void main() {
  group('Registro corto — solo credenciales (Spec 106)', () {
    test('el flujo tiene exactamente owner, phone y pin', () {
      expect(kOnboardingQuestions.map((q) => q.id).toList(),
          ['owner', 'phone', 'pin']);
    });

    test('canRegister se cumple SOLO con credenciales (sin negocio ni logo)',
        () {
      final c = _c();
      expect(c.canRegister, isFalse);
      _fillCredentials(c);
      expect(c.canRegister, isTrue,
          reason: 'nombre del negocio/tipo/logo ya no son requisito (AC-01)');
    });

    test('la IA que llena owner+phone salta a la pregunta de PIN', () {
      final c = _c();
      c.setOwnerName('María');
      c.setOwnerLastName('Gómez');
      c.setPhone('3001234567');
      expect(firstUnansweredIndex(c, {}), 2);
      expect(kOnboardingQuestions[2].id, 'pin');
    });

    test('reset de owner limpia nombre y apellido (undo)', () {
      final c = _c();
      c.setOwnerName('María');
      c.setOwnerLastName('Gómez');
      questionById('owner').reset(c, {});
      expect(c.ownerName, '');
      expect(c.ownerValid, isFalse);
    });

    test('payload mínimo: credenciales + términos + aviso de datos (AC-15)',
        () async {
      Map<String, dynamic>? sent;
      final c = _c(apiCall: (payload) async {
        sent = payload;
        return {'tenant_id': 't-1'};
      });
      _fillCredentials(c);
      c.setAcceptedTerms(true);
      await c.submitWithCaptcha(null);

      expect(sent, isNotNull);
      expect(sent!['owner']['phone'], '3001234567');
      expect(sent!['accept_terms'], isTrue);
      expect(sent!['data_notice_accepted'], isTrue,
          reason: 'FR-13: el aviso de datos viaja en el registro');
      expect(sent!.containsKey('business'), isFalse,
          reason: 'sin datos de negocio no se manda bloque business');
      expect(sent!.containsKey('config'), isFalse,
          reason: 'la configuración la define Vendi, no el registro');
    });

    test('sesión vieja restaurada con negocio SÍ manda sus datos (Art. X)',
        () async {
      Map<String, dynamic>? sent;
      final c = _c(apiCall: (payload) async {
        sent = payload;
        return {'tenant_id': 't-1'};
      });
      _fillCredentials(c);
      c.setBusinessName('La Esquina');
      c.setAcceptedTerms(true);
      await c.submitWithCaptcha(null);

      expect(sent!['business']['name'], 'La Esquina');
    });
  });

  group('PostLoginGate → Vendi (AC-01)', () {
    testWidgets('onboarding incompleto muestra VendiChatScreen', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PostLoginGate(
          ownerName: 'María',
          businessName: 'Mi negocio',
          onboardingCompletedOverride: false,
        ),
      ));
      await tester.pump();
      expect(find.byType(VendiChatScreen), findsOneWidget);
      // Dejar que el turno inicial (degradado en test, sin red) termine.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });
  });
}
