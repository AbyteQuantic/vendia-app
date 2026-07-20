// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_agentic_animated_view.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._result) : super(AuthService());
  final Map<String, dynamic> _result;
  @override
  Future<Map<String, dynamic>> parseOnboarding({
    String text = '',
    Uint8List? audioBytes,
    String mimeType = 'audio/webm',
    String filename = 'onboarding.webm',
    Map<String, dynamic>? current,
  }) async =>
      _result;
}

OnboardingStepperController _ctrl() => OnboardingStepperController(
      apiCall: (_) async => {},
      saveSession: (_) async {},
    );

Widget _wrap(OnboardingStepperController c, ApiService api) => MaterialApp(
      home: ChangeNotifierProvider<OnboardingStepperController>.value(
        value: c,
        child: OnboardingAgenticAnimatedView(
          apiOverride: api,
          persistOverride: false,
        ),
      ),
    );

void _fillCanRegister(OnboardingStepperController c) {
  c.setOwnerName('María');
  c.setOwnerLastName('Gómez');
  c.setPhone('3001234567');
  c.setPin('1234');
  c.setConfirmPin('1234');
  c.setBusinessName('Tienda');
  c.setAddress('Calle 5');
  c.setPrimaryBusinessType('tienda_barrio');
  c.setLogoUrl('https://r2/logo.png');
}

Future<void> pasarSaludo(WidgetTester tester) async {
  await tester.pump();
  final empezar = find.byKey(const Key('os1_empezar'));
  if (empezar.evaluate().isNotEmpty) {
    await tester.tap(empezar);
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('una sola vista: canvas + consola + 1ª pregunta, sin overflow 360dp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await pasarSaludo(tester);

    expect(find.text('¿Cómo se llama usted?'), findsOneWidget);
    expect(find.byKey(const Key('console_ai_input')), findsOneWidget);
    expect(find.byKey(const Key('console_send')), findsOneWidget);
    // En la 1ª pregunta no hay "Atrás".
    expect(find.byKey(const Key('agentic_back')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la IA llena varios campos y el agente SALTA a la pregunta de PIN',
      (tester) async {
    // (el saludo OS1 se pasa tras el primer pump, ver pasarSaludo)
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    final api = _FakeApi({
      'fields': {
        'owner_name': 'María',
        'owner_last_name': 'Gómez',
        'phone': '3001234567',
      },
      'needs_confirmation': <String>[],
      'degraded': false,
    });
    await tester.pumpWidget(_wrap(c, api));
    await pasarSaludo(tester);

    await tester.enterText(find.byKey(const Key('console_ai_input')), 'soy María Gómez 3001234567');
    await tester.ensureVisible(find.byKey(const Key('console_send')));
    await tester.tap(find.byKey(const Key('console_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // owner + phone resueltos → salta a PIN; aparece "Atrás".
    expect(find.text('Cree una clave de 4 a 8 números'), findsOneWidget);
    expect(find.byKey(const Key('agentic_back')), findsOneWidget);
  });

  testWidgets('Atrás retrocede y resetea el último campo contestado',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    // owner y phone ya resueltos → arranca en PIN con trail=[owner,phone].
    c.setOwnerName('María');
    c.setOwnerLastName('Gómez');
    c.setPhone('3001234567');
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    expect(find.text('Cree una clave de 4 a 8 números'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agentic_back')));
    await tester.pump();

    // Vuelve a la pregunta del teléfono y la resetea.
    expect(find.text('Su número de celular'), findsOneWidget);
    expect(c.phone, '');
  });

  testWidgets(
      'con credenciales completas aparece la consola de crear cuenta '
      'con el aviso de datos (Spec 106, AC-15)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    // Spec 106: solo credenciales → canRegister se cumple y se muestra la
    // consola final (la pregunta de tipo ya no existe: la hace Vendi).
    c.setOwnerName('María');
    c.setOwnerLastName('Gómez');
    c.setPhone('3001234567');
    c.setPin('1234');
    c.setConfirmPin('1234');
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    expect(find.byKey(const Key('agentic_create_account')), findsOneWidget);
    expect(find.byKey(const Key('accept_terms_checkbox')), findsOneWidget);
    expect(find.byKey(const Key('data_notice_text')), findsOneWidget);
  });

  testWidgets('"Empezar de nuevo" borra los datos y vuelve al paso 1',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    // Datos restaurados de una sesión anterior → arranca en PIN.
    c.setOwnerName('Pedro');
    c.setOwnerLastName('Ruiz');
    c.setPhone('3009998877');
    c.setBusinessName('Carnitas Al Vapor');
    c.setPrimaryBusinessType('comidas_rapidas');
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    // El botón aparece porque hay datos que descartar.
    expect(find.byKey(const Key('agentic_reset')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agentic_reset')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Confirmación → "Empezar de nuevo".
    expect(find.text('¿Empezar de nuevo?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Empezar de nuevo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Estado limpio: vuelve a la 1ª pregunta y el botón desaparece.
    expect(c.businessName, '');
    expect(c.ownerName, '');
    expect(c.businessType, '');
    expect(find.text('¿Cómo se llama usted?'), findsOneWidget);
    expect(find.byKey(const Key('agentic_reset')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header sin overflow con Atrás + reset + paso a 360dp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    // owner+phone resueltos → arranca en PIN: canBack + _hasAnyData + paso.
    c.setOwnerName('Pedro');
    c.setOwnerLastName('Ruiz');
    c.setPhone('3009998877');
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    expect(find.byKey(const Key('agentic_back')), findsOneWidget);
    expect(find.byKey(const Key('agentic_reset')), findsOneWidget);
    expect(find.byKey(const Key('os1_loader')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cuando canRegister es true muestra el CTA "Crear mi cuenta"',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    _fillCanRegister(c);
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    expect(find.byKey(const Key('agentic_create_account')), findsOneWidget);
    expect(find.textContaining('Todo listo'), findsOneWidget);
  });
}
