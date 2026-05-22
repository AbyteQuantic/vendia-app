// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
//
// T-30 — widget test de OnboardingWizardScreen:
//   - 3 pasos navegables.
//   - "Configurar después" visible en los 3 pasos.
//   - paso 2 pre-marca el checklist según el tipo de negocio.
//   - terminar / saltar dispara PATCH onboarding_completed=true.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/onboarding/onboarding_wizard_screen.dart';
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

  group('OnboardingWizardScreen', () {
    testWidgets('arranca en el paso 1 (tipo de negocio)', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(OnboardingWizardScreen(
        apiOverride: api,
        initialBusinessType: 'tienda_barrio',
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_step_type')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    });

    testWidgets('"Configurar después" visible en los 3 pasos',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(OnboardingWizardScreen(
        apiOverride: api,
        initialBusinessType: 'tienda_barrio',
      )));
      await tester.pumpAndSettle();

      // Paso 1.
      expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);

      // Paso 2.
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_step_capabilities')),
          findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);

      // Paso 3.
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_step_done')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    });

    testWidgets('paso 2 pre-marca el checklist según el tipo (restaurante)',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(OnboardingWizardScreen(
        apiOverride: api,
        initialBusinessType: 'restaurante',
      )));
      await tester.pumpAndSettle();

      // Avanzar al paso 2.
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      // restaurante pre-activa mesas + servicios.
      final tables = tester.widget<SwitchListTile>(
          find.byKey(const Key('onb_cap_tables')));
      final services = tester.widget<SwitchListTile>(
          find.byKey(const Key('onb_cap_services')));
      expect(tables.value, isTrue);
      expect(services.value, isTrue);

      // tienda no pre-activa clientes.
      final customers = tester.widget<SwitchListTile>(
          find.byKey(const Key('onb_cap_customer_management')));
      expect(customers.value, isFalse);
    });

    testWidgets('tienda_barrio NO pre-marca ninguna capacidad',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(OnboardingWizardScreen(
        apiOverride: api,
        initialBusinessType: 'tienda_barrio',
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      final tables = tester.widget<SwitchListTile>(
          find.byKey(const Key('onb_cap_tables')));
      expect(tables.value, isFalse);
    });

    testWidgets('terminar el wizard dispara PATCH onboarding_completed=true',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(OnboardingWizardScreen(
        apiOverride: api,
        initialBusinessType: 'tienda_barrio',
      )));
      await tester.pumpAndSettle();

      // Paso 1 → 2 → 3.
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      // Paso 3 → terminar.
      await tester.tap(find.byKey(const Key('onboarding_finish_button')));
      await tester.pumpAndSettle();

      expect(api.lastPatch, isNotNull);
      expect(api.lastPatch!['onboarding_completed'], isTrue);
    });

    testWidgets('saltar el wizard dispara PATCH onboarding_completed=true',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_wrap(OnboardingWizardScreen(
        apiOverride: api,
        initialBusinessType: 'tienda_barrio',
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      await tester.pumpAndSettle();

      expect(api.lastPatch, isNotNull);
      expect(api.lastPatch!['onboarding_completed'], isTrue);
    });
  });
}
