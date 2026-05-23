// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// T-29 — widget test de WelcomeScreen:
//   - rendea logo + título + botón "Empezar".
//   - tap dispara PATCH onboarding_completed=true.
//   - tras el PATCH se invoca el callback onCompleted.

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
      Map<String, dynamic> data) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(_mockSecureStorage);

  group('WelcomeScreen', () {
    testWidgets('rendea logo, título y botón Empezar', (tester) async {
      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: _FakeApi(),
      )));
      await tester.pump();

      expect(find.byKey(const Key('welcome_logo')), findsOneWidget);
      expect(find.text('¡Bienvenido a VendIA!'), findsOneWidget);
      expect(find.byKey(const Key('welcome_start_button')), findsOneWidget);
      expect(find.text('Empezar'), findsOneWidget);
    });

    testWidgets('tap Empezar dispara PATCH onboarding_completed=true '
        'y llama onCompleted', (tester) async {
      final api = _FakeApi();
      var completed = false;

      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: api,
        onCompleted: () => completed = true,
      )));
      await tester.pump();

      await tester.tap(find.byKey(const Key('welcome_start_button')));
      // Esperamos el await del API + el await del secure-storage write.
      await tester.pumpAndSettle();

      expect(api.lastPatch, isNotNull);
      expect(api.lastPatch!['onboarding_completed'], isTrue);
      expect(completed, isTrue);
    });

    testWidgets('texto explicativo menciona el carrusel de opciones',
        (tester) async {
      await tester.pumpWidget(_wrap(WelcomeScreen(
        apiOverride: _FakeApi(),
      )));
      await tester.pump();

      // El copy debe educar al dueño sobre el reel del Dashboard.
      expect(find.textContaining('carrusel'), findsOneWidget);
    });
  });
}
