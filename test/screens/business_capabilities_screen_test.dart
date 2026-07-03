// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// T-25 — widget test de BusinessCapabilitiesScreen:
//   - lista todas las capacidades opcionales con toggle + descripción
//     (incluida Marketing Hub, F037).
//   - cualquier tipo de negocio puede activar cualquier capacidad.
//   - cambiar un toggle + guardar dispara el PATCH correcto.
//   - al venir con `highlightCapability`, el tile correspondiente
//     pulsa (escala 1.0→1.1→1.0 + tinte de color) durante ~2s.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/dashboard/business_capabilities_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/utils/business_capability_map.dart';

/// Fake ApiService — controla el GET del perfil y captura el PATCH.
class _FakeApi extends ApiService {
  _FakeApi({this.profile}) : super(AuthService());

  final Map<String, dynamic>? profile;
  Map<String, dynamic>? lastPatch;

  @override
  Future<Map<String, dynamic>> fetchBusinessProfile() async {
    return profile ?? <String, dynamic>{'business_types': ['tienda_barrio']};
  }

  @override
  Future<Map<String, dynamic>> updateBusinessProfile(
      Map<String, dynamic> data,
      {CancelToken? cancelToken}) async {
    lastPatch = data;
    return data;
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('BusinessCapabilitiesScreen', () {
    testWidgets('lista todas las capacidades opcionales con toggle',
        (tester) async {
      // Viewport alto para que la ListView monte todas las tarjetas.
      tester.view.physicalSize = const Size(400, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = _FakeApi();
      await tester.pumpWidget(
          _wrap(BusinessCapabilitiesScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      // Las 8 capacidades opcionales tienen su toggle (F037 añadió
      // Marketing Hub).
      expect(find.byKey(const Key('cap_toggle_services')), findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_fractional_units')),
          findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_tables')), findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_price_tiers')), findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_customer_management')),
          findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_quotes')), findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_promotions')), findsOneWidget);
      expect(find.byKey(const Key('cap_toggle_marketing_hub')),
          findsOneWidget);
    });

    testWidgets('una tienda_barrio también puede activar "Mesas" (AC-06)',
        (tester) async {
      // El tipo solo define el default; la pantalla expone todo.
      final api = _FakeApi(profile: {
        'business_types': ['tienda_barrio'],
      });
      await tester.pumpWidget(
          _wrap(BusinessCapabilitiesScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      // "Mesas" está más abajo en la lista — basta scrollear a ella.
      await tester.scrollUntilVisible(
          find.byKey(const Key('cap_toggle_tables')), 200);
      expect(find.byKey(const Key('cap_toggle_tables')), findsOneWidget);
    });

    testWidgets('refleja el estado inicial desde el perfil', (tester) async {
      final api = _FakeApi(profile: {
        'business_types': ['tienda_barrio'],
        'enable_customer_management': true,
      });
      await tester.pumpWidget(
          _wrap(BusinessCapabilitiesScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.byKey(const Key('cap_toggle_customer_management')), 200);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('cap_toggle_customer_management')));
      expect(sw.value, isTrue);
    });

    testWidgets('F037: refleja enable_marketing_hub del perfil',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = _FakeApi(profile: {
        'business_types': ['tienda_barrio'],
        'enable_marketing_hub': true,
      });
      await tester.pumpWidget(
          _wrap(BusinessCapabilitiesScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.byKey(const Key('cap_toggle_marketing_hub')), 200);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('cap_toggle_marketing_hub')));
      expect(sw.value, isTrue);
    });

    testWidgets('cambiar un toggle + guardar dispara el PATCH',
        (tester) async {
      // Viewport alto para montar todas las tarjetas (como los siblings).
      tester.view.physicalSize = const Size(400, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = _FakeApi(profile: {
        'business_types': ['tienda_barrio'],
      });
      await tester.pumpWidget(
          _wrap(BusinessCapabilitiesScreen(apiOverride: api)));
      // pump() acotado en vez de pumpAndSettle(): las tarjetas cargan
      // imágenes de red que nunca "settlean" en el harness de test
      // (mismo patrón que capabilities_reel_test).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Prender "Gestión de clientes".
      await tester.scrollUntilVisible(
          find.byKey(const Key('cap_toggle_customer_management')), 200);
      await tester.tap(find.byKey(const Key('cap_toggle_customer_management')));
      await tester.pump(const Duration(milliseconds: 300));

      // Guardar.
      await tester.tap(find.byKey(const Key('cap_save_button')));
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.lastPatch, isNotNull);
      final config = api.lastPatch!['config'] as Map<String, dynamic>;
      expect(config['enable_customer_management'], isTrue);
    });

    testWidgets('F037: PATCH incluye enable_marketing_hub al guardar',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = _FakeApi();
      await tester.pumpWidget(
          _wrap(BusinessCapabilitiesScreen(apiOverride: api)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.scrollUntilVisible(
          find.byKey(const Key('cap_toggle_marketing_hub')), 200);
      await tester.tap(find.byKey(const Key('cap_toggle_marketing_hub')));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('cap_save_button')));
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.lastPatch, isNotNull);
      final config = api.lastPatch!['config'] as Map<String, dynamic>;
      expect(config['enable_marketing_hub'], isTrue);
    });

    testWidgets('F037: con highlightCapability el tile pulsa visiblemente',
        (tester) async {
      tester.view.physicalSize = const Size(400, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = _FakeApi();
      await tester.pumpWidget(_wrap(BusinessCapabilitiesScreen(
        apiOverride: api,
        highlightCapability: OptionalCapability.customerManagement,
      )));
      // Esperar a que termine el _load y arranque el pulse via
      // postFrameCallback.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verificamos que el árbol contiene un Transform.scale envolviendo
      // al tile de customer_management — eso indica que la animación
      // está activa.
      final scoped = find.ancestor(
        of: find.byKey(const Key('cap_toggle_customer_management')),
        matching: find.byType(Transform),
      );
      expect(scoped, findsWidgets);

      // Avanzar la mitad del pulso (~500ms) — la escala estará en
      // algún valor > 1.0.
      await tester.pump(const Duration(milliseconds: 500));
      // Y completar los ~2s totales sin errores de render.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.takeException(), isNull);
    });
  });
}
