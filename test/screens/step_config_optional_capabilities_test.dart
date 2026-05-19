// Spec: specs/023-capacidades-opcionales-negocio/spec.md
//
// T-10: Widget test de step_config — sección "¿Su negocio también…?"
//
// Criterios cubiertos: AC-01, AC-02, AC-03, FR-02, FR-03
//
// NOTA: la sección de toggles se muestra SOLO después de seleccionar
// un tipo de negocio (requiere un selectedValue != null). Por eso cada
// test selecciona primero el tipo antes de verificar los toggles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/screens/onboarding/steps/step_config.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';
import 'package:vendia_pos/utils/business_capability_map.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildStepConfig({String? initialType}) {
  final ctrl = OnboardingStepperController(
    apiCall: (_) async => {},
    saveSession: (_) async {},
  );
  if (initialType != null) {
    ctrl.setPrimaryBusinessType(initialType);
  }
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<OnboardingStepperController>.value(
        value: ctrl,
        child: const SingleChildScrollView(child: StepConfig()),
      ),
    ),
  );
}

// ── T-10 Tests ────────────────────────────────────────────────────────────────

void main() {
  // ── business_capability_map unit tests ────────────────────────────────────
  group('business_capability_map — impliedCapabilities', () {
    test('tienda_barrio no implica ninguna capacidad', () {
      final implied = impliedCapabilities('tienda_barrio');
      expect(implied, isEmpty);
    });

    test('minimercado no implica ninguna capacidad', () {
      expect(impliedCapabilities('minimercado'), isEmpty);
    });

    test('restaurante implica mesas', () {
      final implied = impliedCapabilities('restaurante');
      expect(implied, contains(OptionalCapability.tables));
      expect(implied, isNot(contains(OptionalCapability.services)));
      expect(implied, isNot(contains(OptionalCapability.fractionalUnits)));
    });

    test('comidas_rapidas implica mesas', () {
      expect(impliedCapabilities('comidas_rapidas'),
          contains(OptionalCapability.tables));
    });

    test('bar implica mesas', () {
      expect(impliedCapabilities('bar'), contains(OptionalCapability.tables));
    });

    test('manufactura implica servicios', () {
      final implied = impliedCapabilities('manufactura');
      expect(implied, contains(OptionalCapability.services));
      expect(implied, isNot(contains(OptionalCapability.tables)));
      expect(implied, isNot(contains(OptionalCapability.fractionalUnits)));
    });

    test('reparacion_muebles implica servicios', () {
      expect(impliedCapabilities('reparacion_muebles'),
          contains(OptionalCapability.services));
    });

    test('emprendimiento_general implica servicios', () {
      expect(impliedCapabilities('emprendimiento_general'),
          contains(OptionalCapability.services));
    });

    test('deposito_construccion implica granel', () {
      final implied = impliedCapabilities('deposito_construccion');
      expect(implied, contains(OptionalCapability.fractionalUnits));
      expect(implied, isNot(contains(OptionalCapability.tables)));
      expect(implied, isNot(contains(OptionalCapability.services)));
    });

    test('null no implica ninguna capacidad', () {
      expect(impliedCapabilities(null), isEmpty);
    });
  });

  group('business_capability_map — toggleableCapabilities', () {
    test('tienda_barrio: los 3 toggles son visibles', () {
      final toggleable = toggleableCapabilities('tienda_barrio');
      expect(toggleable, contains(OptionalCapability.tables));
      expect(toggleable, contains(OptionalCapability.services));
      expect(toggleable, contains(OptionalCapability.fractionalUnits));
    });

    test('restaurante: mesas no es toggleable (ya implícita)', () {
      final toggleable = toggleableCapabilities('restaurante');
      expect(toggleable, isNot(contains(OptionalCapability.tables)));
      expect(toggleable, contains(OptionalCapability.services));
      expect(toggleable, contains(OptionalCapability.fractionalUnits));
    });

    test('manufactura: servicios no es toggleable (ya implícita)', () {
      final toggleable = toggleableCapabilities('manufactura');
      expect(toggleable, isNot(contains(OptionalCapability.services)));
      expect(toggleable, contains(OptionalCapability.tables));
      expect(toggleable, contains(OptionalCapability.fractionalUnits));
    });

    test('deposito: granel no es toggleable (ya implícita)', () {
      final toggleable = toggleableCapabilities('deposito_construccion');
      expect(toggleable, isNot(contains(OptionalCapability.fractionalUnits)));
      expect(toggleable, contains(OptionalCapability.tables));
      expect(toggleable, contains(OptionalCapability.services));
    });
  });

  // ── Widget tests ──────────────────────────────────────────────────────────
  group('StepConfig — sección de capacidades opcionales (T-10)', () {
    // AC-01: Tienda de Barrio → los 3 toggles en OFF
    testWidgets(
        'AC-01: tienda_barrio muestra los 3 toggles de capacidades opcionales en OFF',
        (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'tienda_barrio'));
      await tester.pumpAndSettle();

      // La sección debe ser visible
      expect(find.byKey(const Key('optional_caps_section')), findsOneWidget);

      // Los 3 toggles deben existir
      expect(find.byKey(const Key('toggle_services')), findsOneWidget);
      expect(find.byKey(const Key('toggle_fractional')), findsOneWidget);
      expect(find.byKey(const Key('toggle_tables')), findsOneWidget);

      // Todos deben estar en OFF (valor = false)
      final servicesSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_services')));
      final fractionalSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_fractional')));
      final tablesSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_tables')));

      expect(servicesSwitch.value, isFalse,
          reason: 'toggle servicios debe iniciar en OFF');
      expect(fractionalSwitch.value, isFalse,
          reason: 'toggle granel debe iniciar en OFF');
      expect(tablesSwitch.value, isFalse,
          reason: 'toggle mesas debe iniciar en OFF');
    });

    // AC-02: Restaurante → toggle de mesas NO aparece
    testWidgets(
        'AC-02: restaurante oculta el toggle de mesas (ya implícito), muestra servicios y granel',
        (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'restaurante'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('optional_caps_section')), findsOneWidget);
      // mesas NO aparece
      expect(find.byKey(const Key('toggle_tables')), findsNothing);
      // servicios y granel SÍ aparecen
      expect(find.byKey(const Key('toggle_services')), findsOneWidget);
      expect(find.byKey(const Key('toggle_fractional')), findsOneWidget);
    });

    // AC-02 extensión: bar y comidas_rapidas también implican mesas
    testWidgets('bar oculta el toggle de mesas', (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'bar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_tables')), findsNothing);
    });

    testWidgets('comidas_rapidas oculta el toggle de mesas', (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'comidas_rapidas'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_tables')), findsNothing);
    });

    // AC-03: Manufactura → toggle de servicios NO aparece
    testWidgets(
        'AC-03: manufactura oculta el toggle de servicios (ya implícito), muestra mesas y granel',
        (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'manufactura'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('optional_caps_section')), findsOneWidget);
      // servicios NO aparece
      expect(find.byKey(const Key('toggle_services')), findsNothing);
      // mesas y granel SÍ aparecen
      expect(find.byKey(const Key('toggle_tables')), findsOneWidget);
      expect(find.byKey(const Key('toggle_fractional')), findsOneWidget);
    });

    testWidgets('reparacion_muebles oculta el toggle de servicios',
        (tester) async {
      await tester.pumpWidget(
          _buildStepConfig(initialType: 'reparacion_muebles'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_services')), findsNothing);
    });

    testWidgets('emprendimiento_general oculta el toggle de servicios',
        (tester) async {
      await tester.pumpWidget(
          _buildStepConfig(initialType: 'emprendimiento_general'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_services')), findsNothing);
    });

    testWidgets('deposito_construccion oculta el toggle de granel',
        (tester) async {
      await tester.pumpWidget(
          _buildStepConfig(initialType: 'deposito_construccion'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_fractional')), findsNothing);
    });

    // FR-03: toggles arrancan en OFF por defecto
    testWidgets('FR-03: los toggles visibles arrancan en OFF', (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'minimercado'));
      await tester.pumpAndSettle();

      final servicesSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_services')));
      final fractionalSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_fractional')));
      final tablesSwitch = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_tables')));

      expect(servicesSwitch.value, isFalse);
      expect(fractionalSwitch.value, isFalse);
      expect(tablesSwitch.value, isFalse);
    });

    // La sección NO aparece si no se ha seleccionado ningún tipo
    testWidgets('sin tipo seleccionado no muestra la sección de capacidades',
        (tester) async {
      await tester.pumpWidget(_buildStepConfig());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('optional_caps_section')), findsNothing);
    });

    // Interacción: activar un toggle lo deja en ON
    testWidgets('activar el toggle de servicios lo pone en ON', (tester) async {
      await tester.pumpWidget(_buildStepConfig(initialType: 'tienda_barrio'));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('toggle_services'));
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();

      SwitchListTile sw = tester.widget<SwitchListTile>(switchFinder);
      expect(sw.value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      sw = tester.widget<SwitchListTile>(switchFinder);
      expect(sw.value, isTrue);
    });

    // Cambio de tipo: limpiar el toggle que el nuevo tipo ya implica
    testWidgets(
        'al cambiar a "manufactura" el toggle de servicios desaparece y el state se limpia',
        (tester) async {
      final ctrl = OnboardingStepperController(
        apiCall: (_) async => {},
        saveSession: (_) async {},
      );
      // Empezar con tienda_barrio y activar el toggle de servicios
      ctrl.setPrimaryBusinessType('tienda_barrio');
      ctrl.offersServices = true;

      final widget = MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<OnboardingStepperController>.value(
            value: ctrl,
            child: const SingleChildScrollView(child: StepConfig()),
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // Confirmar que el toggle está ON
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('toggle_services')));
      expect(sw.value, isTrue);

      // Cambiar el tipo a manufactura (que ya implica servicios)
      ctrl.setPrimaryBusinessType('manufactura');
      await tester.pumpAndSettle();

      // El toggle de servicios ya no debe aparecer
      expect(find.byKey(const Key('toggle_services')), findsNothing);
      // Y el estado del controller debe estar en false
      expect(ctrl.offersServices, isFalse);
    });
  });
}
