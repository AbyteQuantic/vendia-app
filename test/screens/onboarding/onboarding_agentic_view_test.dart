// Spec: specs/045-onboarding-agentic/onboarding_agentic_spec.md
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_agentic_view.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/voice_recorder.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._result) : super(AuthService());
  final Map<String, dynamic> _result;
  Uint8List? lastAudio;
  @override
  Future<Map<String, dynamic>> parseOnboarding({
    String text = '',
    Uint8List? audioBytes,
    String mimeType = 'audio/webm',
    String filename = 'onboarding.webm',
    Map<String, dynamic>? current,
  }) async {
    lastAudio = audioBytes;
    return _result;
  }
}

/// Recorder falso (web-safe, sin micrófono real) — espejo del de voz F020.
class _FakeRecorder implements AudioRecorder {
  bool started = false;
  bool stopped = false;
  @override
  Future<bool> hasPermission({bool request = true}) async => true;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    started = true;
  }
  @override
  Future<String?> stop() async {
    stopped = true;
    return 'fake-clip';
  }
  @override
  Future<void> dispose() async {}
  @override
  noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakeRecorder: ${i.memberName}');
}

Future<String> _fakePath() async => 'fake-clip';
Future<RecordedAudio> _fakeAudio(String _) async => RecordedAudio(
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
      mimeType: 'audio/webm',
      filename: 'onboarding.webm',
    );

OnboardingStepperController _ctrl({Map<String, dynamic>? captured}) =>
    OnboardingStepperController(
      apiCall: (p) async {
        captured?.addAll(p);
        return {};
      },
      saveSession: (_) async {},
    );

Widget _wrap(
  OnboardingStepperController c,
  ApiService api, {
  AudioRecorder? recorder,
  bool persist = false,
}) =>
    MaterialApp(
      home: ChangeNotifierProvider<OnboardingStepperController>.value(
        value: c,
        child: OnboardingAgenticView(
          apiOverride: api,
          recorderOverride: recorder,
          resolvePathOverride: _fakePath,
          readAudioOverride: _fakeAudio,
          persistOverride: persist,
        ),
      ),
    );

void _fillAllValid(OnboardingStepperController c) {
  c.setOwnerName('María');
  c.setOwnerLastName('Gómez');
  c.setPhone('3001234567');
  c.setPin('1234');
  c.setConfirmPin('1234');
  c.setBusinessName('Tienda Doña Marta');
  c.setAddress('Calle 5 #3-20');
  c.setPrimaryBusinessType('tienda_barrio');
  c.setLogoUrl('https://r2/logo.png');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('renderiza las 6 Smart Cards + saludo + input + CTA',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    expect(find.text('Vamos a crear su negocio'), findsOneWidget);
    for (final id in [
      'sus_datos',
      'negocio',
      'local',
      'tipo',
      'logo',
      'empleados'
    ]) {
      expect(find.byKey(Key('agentic_card_$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('agentic_input')), findsOneWidget);
    expect(find.byKey(const Key('agentic_send')), findsOneWidget);
    expect(find.byKey(const Key('agentic_create_account')), findsOneWidget);
    expect(tester.takeException(), isNull); // sin overflow a 360dp
  });

  testWidgets('CTA deshabilitado hasta canRegister; luego habilitado',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    ElevatedButton cta() => tester.widget<ElevatedButton>(
        find.byKey(const Key('agentic_create_account')));
    expect(cta().onPressed, isNull); // deshabilitado

    _fillAllValid(c);
    await tester.pump();
    expect(cta().onPressed, isNotNull); // habilitado
  });

  testWidgets('la IA rellena las cards y muestra el badge "sugerido por IA"',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    final fake = _FakeApi({
      'fields': {
        'owner_name': 'María',
        'business_name': 'Doña Marta',
        'business_type': 'tienda_barrio',
      },
      'needs_confirmation': <String>[],
      'degraded': false,
    });
    await tester.pumpWidget(_wrap(c, fake));
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('agentic_input')), 'soy María, tienda Doña Marta');
    await tester.tap(find.byKey(const Key('agentic_send')));
    await tester.pump(); // dispara parse
    await tester.pump(const Duration(milliseconds: 100));

    expect(c.businessType, 'tienda_barrio');
    expect(c.businessName, 'Doña Marta');
    expect(find.textContaining('sugerido por IA'), findsWidgets);
  });

  testWidgets('respuesta degraded muestra el banner discreto', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    final fake = _FakeApi({'degraded': true, 'reason': 'ai_unavailable'});
    await tester.pumpWidget(_wrap(c, fake));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('agentic_input')), 'hola');
    await tester.tap(find.byKey(const Key('agentic_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Sin conexión con la IA'), findsOneWidget);
  });

  testWidgets('tocar la card "Sus datos" abre el editor y confirma al llenar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    await tester.pumpWidget(_wrap(c, _FakeApi(const {})));
    await tester.pump();

    await tester.tap(find.byKey(const Key('agentic_card_sus_datos')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit_owner_name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit_owner_name')), 'María');
    await tester.enterText(find.byKey(const Key('edit_owner_phone')), '3001234567');
    await tester.enterText(find.byKey(const Key('edit_owner_pin')), '1234');
    await tester.enterText(
        find.byKey(const Key('edit_owner_pin_confirm')), '1234');
    await tester.tap(find.byKey(const Key('sheet_done')));
    await tester.pumpAndSettle();

    expect(c.ownerName, 'María');
    expect(c.phone, '3001234567');
    expect(c.pinValid, isTrue);
    expect(c.pinConfirmed, isTrue);
  });

  testWidgets('dictado por voz: grabar→parar manda audio a la IA y rellena',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    final fake = _FakeApi({
      'fields': {'business_name': 'Doña Marta'},
      'needs_confirmation': <String>[],
      'degraded': false,
    });
    final recorder = _FakeRecorder();
    await tester.pumpWidget(_wrap(c, fake, recorder: recorder));
    await tester.pump();

    // Primer toque: empieza a grabar (el ícono pasa a "stop").
    await tester.tap(find.byKey(const Key('agentic_mic')));
    await tester.pump();
    expect(recorder.started, isTrue);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    // Segundo toque: para, lee el audio y lo manda a la IA.
    await tester.tap(find.byKey(const Key('agentic_mic')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(recorder.stopped, isTrue);
    expect(fake.lastAudio, isNotNull); // viajó el audio
    expect(c.businessName, 'Doña Marta');
  });

  testWidgets('persistencia: restaura el estado capturado tras un refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'vendia:onboarding:current': '{"owner_name":"María",'
          '"business_name":"Doña Marta","business_type":"tienda_barrio",'
          '"address":"Calle 5"}',
    });
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = _ctrl();
    await tester.pumpWidget(_wrap(c, _FakeApi(const {}), persist: true));
    await tester.pump(); // initState → _restore (async)
    await tester.pump(const Duration(milliseconds: 50));

    expect(c.ownerName, 'María');
    expect(c.businessName, 'Doña Marta');
    expect(c.businessType, 'tienda_barrio');
    expect(c.address, 'Calle 5');
  });
}
