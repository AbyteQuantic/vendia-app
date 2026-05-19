// Spec: specs/023-capacidades-opcionales-negocio/spec.md
//
// T-13: Widget test de business_profile_screen.dart
// Criterios cubiertos: AC-05, AC-06, FR-06
//
// La pantalla hace fetch a la API al init. En tests usamos un ApiService fake
// via una subclase testable del State — sin embargo, BusinessProfileScreen
// instancia ApiService directamente en initState. Para testear la sección de
// toggles sin network, extraemos la lógica relevante a través de la nueva
// clase pública BusinessProfileToggles y testamos eso directamente.
//
// Los widget tests de _BusinessProfileScreenState._buildOptionalCapabilities
// se hacen via un widget wrapper que aísla esa sección.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/utils/business_capability_map.dart';
import 'package:vendia_pos/widgets/optional_capabilities_section.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wrapper que aisla la sección de capacidades opcionales para tests.
Widget _buildSection({
  required String? selectedType,
  required FeatureFlags flags,
  required ValueNotifier<bool> offersServices,
  required ValueNotifier<bool> sellsByWeight,
  required ValueNotifier<bool> hasTables,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OptionalCapabilitiesSection(
          selectedType: selectedType,
          flags: flags,
          offersServices: offersServices,
          sellsByWeight: sellsByWeight,
          hasTables: hasTables,
        ),
      ),
    ),
  );
}

// ── T-13 Tests ────────────────────────────────────────────────────────────────

void main() {
  group('OptionalCapabilitiesSection — derivación de estado desde feature_flags (T-13)', () {
    // AC-05: los toggles reflejan los feature_flags actuales
    testWidgets(
        'AC-05: toggle servicios ON cuando enable_services=true y el tipo no lo implica',
        (tester) async {
      const flags = FeatureFlags(enableServices: true);
      final offersServices = ValueNotifier<bool>(
        flags.enableServices &&
            !impliedCapabilities('tienda_barrio')
                .contains(OptionalCapability.services),
      );
      final sellsByWeight = ValueNotifier<bool>(false);
      final hasTables = ValueNotifier<bool>(false);

      await tester.pumpWidget(_buildSection(
        selectedType: 'tienda_barrio',
        flags: flags,
        offersServices: offersServices,
        sellsByWeight: sellsByWeight,
        hasTables: hasTables,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_services')), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_services')));
      expect(sw.value, isTrue,
          reason: 'enable_services=true y tipo no lo implica → toggle ON');
    });

    testWidgets(
        'toggle servicios OFF cuando enable_services=false',
        (tester) async {
      const flags = FeatureFlags(enableServices: false);
      final offersServices = ValueNotifier<bool>(false);
      final sellsByWeight = ValueNotifier<bool>(false);
      final hasTables = ValueNotifier<bool>(false);

      await tester.pumpWidget(_buildSection(
        selectedType: 'tienda_barrio',
        flags: flags,
        offersServices: offersServices,
        sellsByWeight: sellsByWeight,
        hasTables: hasTables,
      ));
      await tester.pumpAndSettle();

      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_services')));
      expect(sw.value, isFalse);
    });

    testWidgets(
        'toggle mesas ON cuando enable_tables=true y tipo no lo implica',
        (tester) async {
      const flags = FeatureFlags(enableTables: true);
      final offersServices = ValueNotifier<bool>(false);
      final sellsByWeight = ValueNotifier<bool>(false);
      final hasTables = ValueNotifier<bool>(true); // derivado del flag

      await tester.pumpWidget(_buildSection(
        selectedType: 'tienda_barrio',
        flags: flags,
        offersServices: offersServices,
        sellsByWeight: sellsByWeight,
        hasTables: hasTables,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_tables')), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_tables')));
      expect(sw.value, isTrue);
    });

    testWidgets(
        'toggle granel ON cuando enable_fractional_units=true y tipo no lo implica',
        (tester) async {
      const flags = FeatureFlags(enableFractionalUnits: true);
      final offersServices = ValueNotifier<bool>(false);
      final sellsByWeight = ValueNotifier<bool>(true);
      final hasTables = ValueNotifier<bool>(false);

      await tester.pumpWidget(_buildSection(
        selectedType: 'minimercado',
        flags: flags,
        offersServices: offersServices,
        sellsByWeight: sellsByWeight,
        hasTables: hasTables,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_fractional')), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_fractional')));
      expect(sw.value, isTrue);
    });

    // AC-06: un toggle que no está implicado por el tipo puede apagarse
    testWidgets(
        'AC-06: toggle de mesas se puede desactivar (tienda_barrio no implica mesas)',
        (tester) async {
      const flags = FeatureFlags(enableTables: true);
      final hasTables = ValueNotifier<bool>(true);

      await tester.pumpWidget(_buildSection(
        selectedType: 'tienda_barrio',
        flags: flags,
        offersServices: ValueNotifier<bool>(false),
        sellsByWeight: ValueNotifier<bool>(false),
        hasTables: hasTables,
      ));
      await tester.pumpAndSettle();

      // Está en ON
      SwitchListTile sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_tables')));
      expect(sw.value, isTrue);

      // Desactivar
      await tester.tap(find.byKey(const Key('toggle_tables')));
      await tester.pumpAndSettle();

      // Ahora en OFF
      expect(hasTables.value, isFalse);
    });

    // El toggle NO aparece cuando el tipo ya lo implica
    testWidgets(
        'toggle mesas NO aparece cuando el tipo es restaurante (ya implícito)',
        (tester) async {
      const flags = FeatureFlags(enableTables: true);

      await tester.pumpWidget(_buildSection(
        selectedType: 'restaurante',
        flags: flags,
        offersServices: ValueNotifier<bool>(false),
        sellsByWeight: ValueNotifier<bool>(false),
        hasTables: ValueNotifier<bool>(true),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_tables')), findsNothing);
    });

    testWidgets(
        'toggle servicios NO aparece cuando el tipo es manufactura (ya implícito)',
        (tester) async {
      const flags = FeatureFlags(enableServices: true);

      await tester.pumpWidget(_buildSection(
        selectedType: 'manufactura',
        flags: flags,
        offersServices: ValueNotifier<bool>(true),
        sellsByWeight: ValueNotifier<bool>(false),
        hasTables: ValueNotifier<bool>(false),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_services')), findsNothing);
    });

    // Sin tipo seleccionado → sección no visible
    testWidgets('sin selectedType no muestra la sección', (tester) async {
      await tester.pumpWidget(_buildSection(
        selectedType: null,
        flags: const FeatureFlags(),
        offersServices: ValueNotifier<bool>(false),
        sellsByWeight: ValueNotifier<bool>(false),
        hasTables: ValueNotifier<bool>(false),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('optional_caps_section')), findsNothing);
    });
  });

  group('OptionalCapabilitiesSection — interacción de toggles', () {
    testWidgets('activar toggle_services actualiza el ValueNotifier',
        (tester) async {
      final offersServices = ValueNotifier<bool>(false);

      await tester.pumpWidget(_buildSection(
        selectedType: 'tienda_barrio',
        flags: const FeatureFlags(),
        offersServices: offersServices,
        sellsByWeight: ValueNotifier<bool>(false),
        hasTables: ValueNotifier<bool>(false),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('toggle_services')));
      await tester.tap(find.byKey(const Key('toggle_services')));
      await tester.pumpAndSettle();

      expect(offersServices.value, isTrue);
    });

    testWidgets('activar toggle_fractional actualiza el ValueNotifier',
        (tester) async {
      final sellsByWeight = ValueNotifier<bool>(false);

      await tester.pumpWidget(_buildSection(
        selectedType: 'tienda_barrio',
        flags: const FeatureFlags(),
        offersServices: ValueNotifier<bool>(false),
        sellsByWeight: sellsByWeight,
        hasTables: ValueNotifier<bool>(false),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('toggle_fractional')));
      await tester.tap(find.byKey(const Key('toggle_fractional')));
      await tester.pumpAndSettle();

      expect(sellsByWeight.value, isTrue);
    });
  });
}
