// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// Widget tests del WelcomeScreen — tour educativo de 6 pasos
// post-login:
//   - Step 1 muestra logo + título + botón "Siguiente".
//   - El botón "Saltar" dispara PATCH onboarding_completed=true.
//   - El step 5 menciona el carrusel del Dashboard (educa al dueño
//     sobre el mecanismo de descubrimiento de capacidades).
//   - Al llegar al último paso el botón muestra "Empezar" y al
//     tocarlo dispara PATCH + onCompleted.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/onboarding/welcome_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  Map<String, dynamic>? lastPatch;

  @override
  Future<Map<String, dynamic>> updateBusinessProfile(
      Map<String, dynamic> data,
      {CancelToken? cancelToken}) async {
    lastPatch = data;
    return data;
  }
}

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
}

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Avanza el PageView del tour [steps] veces tocando "Siguiente".
Future<void> _advanceSteps(WidgetTester tester, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.tap(find.byKey(const Key('welcome_start_button')));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(_mockSecureStorage);

  group('WelcomeScreen — tour educativo', () {
    testWidgets('paso 1: logo + título + botón Siguiente', (tester) async {
      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: _FakeApi(),
      )));
      await tester.pump();

      expect(find.byKey(const Key('welcome_logo')), findsOneWidget);
      expect(find.text('¡Bienvenido a VendIA!'), findsOneWidget);
      expect(find.byKey(const Key('welcome_start_button')), findsOneWidget);
      // En el primer paso el botón principal dice "Siguiente"
      // (los pasos intermedios mantienen el copy).
      expect(find.text('Siguiente'), findsOneWidget);
    });

    testWidgets('botón Saltar dispara PATCH y onCompleted',
        (tester) async {
      final api = _FakeApi();
      var completed = false;

      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: api,
        onCompleted: () => completed = true,
      )));
      await tester.pump();

      // El botón Saltar está disponible en cualquier paso menos el último.
      await tester.tap(find.text('Saltar'));
      await tester.pumpAndSettle();

      expect(api.lastPatch, isNotNull);
      expect(api.lastPatch!['onboarding_completed'], isTrue);
      expect(completed, isTrue);
    });

    testWidgets('paso 5 (Descubrir más) menciona el carrusel',
        (tester) async {
      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: _FakeApi(),
      )));
      await tester.pump();

      // Avanzar 4 pasos para llegar al de "Descubrir más opciones"
      // (índice 4, posición 5/6).
      await _advanceSteps(tester, 4);

      expect(find.text('Descubrir más opciones'), findsOneWidget);
      expect(find.textContaining('carrusel'), findsOneWidget);
    });

    testWidgets('último paso muestra "Empezar" y dispara PATCH al tocarlo',
        (tester) async {
      final api = _FakeApi();
      var completed = false;

      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: api,
        onCompleted: () => completed = true,
      )));
      await tester.pump();

      // 5 toques de "Siguiente" para llegar al step 6 (índice 5).
      await _advanceSteps(tester, 5);

      // Ya no hay botón Saltar en el último paso.
      expect(find.text('Saltar'), findsNothing);
      expect(find.text('Empezar'), findsOneWidget);
      expect(find.text('¡Todo listo!'), findsOneWidget);

      // Tap final.
      await tester.tap(find.byKey(const Key('welcome_start_button')));
      await tester.pumpAndSettle();

      expect(api.lastPatch, isNotNull);
      expect(api.lastPatch!['onboarding_completed'], isTrue);
      expect(completed, isTrue);
    });
  });
}
