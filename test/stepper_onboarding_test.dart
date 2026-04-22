import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/screens/dashboard/main_dashboard_screen.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────
//
// The stepper has 6 steps (owner → business → branches → config → logo →
// employees). Tests were originally written for the 4-step legacy flow —
// this file was rewritten alongside migration 020/021 to match.
//
// Business-type keys come from StepConfig._types (the Dart const list).
// The value whitelist (`tienda_barrio`, `reparacion_muebles`, etc.) is
// authoritative on the backend — see models.ValidBusinessTypes.

final _successResponse = {
  'token': 'mock-jwt-token',
  'tenant_id': 42,
  'owner_name': 'Pedro Martínez',
  'business_name': 'Tienda Don Pedro',
  'business_types': ['tienda_barrio'],
  'feature_flags': {
    'enable_tables': false,
    'enable_kds': false,
    'enable_tips': false,
    'enable_services': false,
    'enable_custom_billing': false,
    'enable_fractional_units': false,
  },
};

Widget buildTestWidget({
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? apiCall,
  Future<void> Function(Map<String, dynamic>)? saveSession,
}) {
  final ctrl = OnboardingStepperController(
    apiCall: apiCall ?? (_) async => _successResponse,
    saveSession: saveSession ?? (_) async {},
  );

  return MaterialApp(
    home: ChangeNotifierProvider<OnboardingStepperController>.value(
      value: ctrl,
      child: const OnboardingStepper(),
    ),
  );
}

/// Fills the Owner form and taps Next. Includes the confirm-PIN field
/// that the current step validates against the primary PIN.
Future<void> fillAndAdvanceStep1(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('owner_name')), 'Pedro');
  await tester.enterText(find.byKey(const Key('owner_lastname')), 'Martínez');
  await tester.enterText(find.byKey(const Key('owner_phone')), '3101234567');
  await tester.enterText(find.byKey(const Key('owner_pin')), '1234');
  await tester.enterText(
      find.byKey(const Key('owner_pin_confirm')), '1234');
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

Future<void> fillAndAdvanceStep2(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('biz_name')), 'Tienda Don Pedro');
  await tester.enterText(find.byKey(const Key('biz_razon')), 'Pedro SAS');
  await tester.enterText(find.byKey(const Key('biz_nit')), '900000001-0');
  // biz_address only renders once the GPS button has resolved a
  // location — the test flow doesn't trigger GPS, so the address
  // field is intentionally not present. validate() only enforces
  // biz_name, so we can advance without it.
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

/// Branches step has no required selection — just tap Next to advance.
Future<void> advanceStep3Branches(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

/// Picks the tienda_barrio tile (key `btype_tienda`) and advances.
/// Uses ensureVisible because the GridView.count inside the stepper
/// layouts 9 tiles that can overflow the default 600x800 test viewport.
Future<void> selectAndAdvanceStep4Config(WidgetTester tester) async {
  final tile = find.byKey(const Key('btype_tienda'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile, warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

/// Logo step is optional — skip forward to employees.
Future<void> advanceStep5Logo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

/// Full happy path from step 1 to step 6 (employees / submit).
Future<void> advanceToEmployees(WidgetTester tester) async {
  await fillAndAdvanceStep1(tester);
  await fillAndAdvanceStep2(tester);
  await advanceStep3Branches(tester);
  await selectAndAdvanceStep4Config(tester);
  await advanceStep5Logo(tester);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('OnboardingStepper — Paso 1: Propietario', () {
    testWidgets('muestra los 4 campos requeridos del propietario',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(const Key('owner_name')), findsOneWidget);
      expect(find.byKey(const Key('owner_lastname')), findsOneWidget);
      expect(find.byKey(const Key('owner_phone')), findsOneWidget);
      expect(find.byKey(const Key('owner_pin')), findsOneWidget);
      expect(find.byKey(const Key('owner_pin_confirm')), findsOneWidget);
    });

    testWidgets('muestra botón Siguiente', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(const Key('btn_next')), findsOneWidget);
    });

    testWidgets('no muestra botón Atrás en el primer paso', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(const Key('btn_back')), findsNothing);
    });

    testWidgets('Siguiente con campos vacíos muestra errores de validación',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      final errorFinders = [
        find.text('Ingrese su nombre'),
        find.text('Ingrese su apellido'),
        find.text('Ingrese su número'),
      ];
      final errorsFound = errorFinders.where((f) => tester.any(f)).length;
      expect(errorsFound, greaterThan(0),
          reason: 'Debe haber al menos un error de validación visible');
    });

    testWidgets('PIN demasiado corto muestra error de validación',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.enterText(find.byKey(const Key('owner_name')), 'Pedro');
      await tester.enterText(find.byKey(const Key('owner_lastname')), 'M');
      await tester.enterText(
          find.byKey(const Key('owner_phone')), '3101234567');
      await tester.enterText(find.byKey(const Key('owner_pin')), '12');
      await tester.enterText(
          find.byKey(const Key('owner_pin_confirm')), '12');
      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      expect(find.text('Mínimo 4 dígitos'), findsOneWidget);
    });
  });

  group('OnboardingStepper — Navegación entre pasos', () {
    testWidgets('avanza al Paso 2 al completar correctamente el Paso 1',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);

      expect(find.byKey(const Key('biz_name')), findsOneWidget);
    });

    testWidgets('muestra botón Atrás a partir del Paso 2', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);

      expect(find.byKey(const Key('btn_back')), findsOneWidget);
    });

    testWidgets('botón Atrás regresa al Paso 1 desde el Paso 2',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);

      await tester.tap(find.byKey(const Key('btn_back')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('owner_name')), findsOneWidget);
    });

    testWidgets('navega los 6 pasos hasta Empleados', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await fillAndAdvanceStep1(tester);
      expect(find.byKey(const Key('biz_name')), findsOneWidget);

      await fillAndAdvanceStep2(tester);
      // Step 3 (branches) renders the single/multi branch buttons.
      expect(find.byKey(const Key('btn_single_branch')), findsOneWidget);

      await advanceStep3Branches(tester);
      expect(find.byKey(const Key('step_config')), findsOneWidget);

      await selectAndAdvanceStep4Config(tester);
      // Step 5 (logo) — no specific key required, just moves on.
      await advanceStep5Logo(tester);
      expect(find.byKey(const Key('step_employees')), findsOneWidget);
    });
  });

  group('OnboardingStepper — Paso 2: Tienda', () {
    testWidgets('muestra los campos de datos del negocio', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);

      expect(find.byKey(const Key('biz_name')), findsOneWidget);
      expect(find.byKey(const Key('biz_razon')), findsOneWidget);
      expect(find.byKey(const Key('biz_nit')), findsOneWidget);
      // biz_address is GPS-gated and not required for navigation.
      expect(find.byKey(const Key('btn_gps_location')), findsOneWidget);
    });

    testWidgets('Siguiente sin nombre de negocio muestra error',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);

      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      expect(find.text('Ingrese el nombre del negocio'), findsOneWidget);
    });
  });

  group('OnboardingStepper — Paso 4: Configuración', () {
    testWidgets('muestra las tarjetas de la taxonomía unificada',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await advanceStep3Branches(tester);

      // Sample 4 of the 9 unified business types to confirm the grid
      // renders the new taxonomy. Keys come from StepConfig._types.
      expect(find.byKey(const Key('btype_tienda')), findsOneWidget);
      expect(find.byKey(const Key('btype_restaurante')), findsOneWidget);
      expect(find.byKey(const Key('btype_reparacion_muebles')),
          findsOneWidget);
      expect(find.byKey(const Key('btype_emprendimiento')), findsOneWidget);
    });

    testWidgets('Siguiente sin seleccionar tipo de negocio no avanza',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await advanceStep3Branches(tester);

      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      // The stepper short-circuits the nextStep() call when
      // businessTypes is empty — so we should still be on step_config.
      expect(find.byKey(const Key('step_config')), findsOneWidget);
      expect(
        find.text('Seleccione al menos un tipo de negocio'),
        findsOneWidget,
      );
    });

    testWidgets('seleccionar una tarjeta la registra en el controller',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await advanceStep3Branches(tester);

      final tile = find.byKey(const Key('btype_minimercado'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile, warnIfMissed: false);
      await tester.pump();

      final ctrl = tester
          .element(find.byType(OnboardingStepper))
          .read<OnboardingStepperController>();
      expect(ctrl.businessType, equals('minimercado'));
      expect(ctrl.businessTypes, contains('minimercado'));
    });

    testWidgets(
        'selección única: tocar otra tarjeta reemplaza el valor anterior',
        (tester) async {
      // Multi-select was retired to kill ambiguous feature-flag
      // combos (bar+manufactura enabling both mesas and services).
      // Second tap REPLACES — never accumulates.
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await advanceStep3Branches(tester);

      final tienda = find.byKey(const Key('btype_tienda'));
      final reparacion = find.byKey(const Key('btype_reparacion_muebles'));

      await tester.ensureVisible(tienda);
      await tester.pumpAndSettle();
      await tester.tap(tienda, warnIfMissed: false);
      await tester.pumpAndSettle();

      final ctrl = tester
          .element(find.byType(OnboardingStepper))
          .read<OnboardingStepperController>();
      expect(ctrl.businessTypes, equals(['tienda_barrio']));

      await tester.ensureVisible(reparacion);
      await tester.pumpAndSettle();
      await tester.tap(reparacion, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(ctrl.businessTypes, equals(['reparacion_muebles']),
          reason: 'el segundo tap reemplaza, no acumula');
    });
  });

  group('OnboardingStepper — Paso 6: Empleados', () {
    testWidgets('muestra la pregunta de empleados y las 2 opciones',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await advanceToEmployees(tester);

      expect(find.byKey(const Key('step_employees')), findsOneWidget);
      expect(find.byKey(const Key('emp_yes')), findsOneWidget);
      expect(find.byKey(const Key('emp_no')), findsOneWidget);
    });

    testWidgets('seleccionar NO muestra mensaje de cajero por defecto',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await advanceToEmployees(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();

      expect(
        find.text('Te asignaremos como el cajero principal por defecto'),
        findsOneWidget,
      );
    });

    testWidgets('muestra botón Finalizar Registro en el último paso',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await advanceToEmployees(tester);

      expect(find.byKey(const Key('btn_submit')), findsOneWidget);
    });
  });

  group('OnboardingStepper — Submit y Navegación', () {
    testWidgets('submit llama al API con el payload de la taxonomía unificada',
        (tester) async {
      Map<String, dynamic>? capturedPayload;

      await tester.pumpWidget(buildTestWidget(
        apiCall: (payload) async {
          capturedPayload = payload;
          return _successResponse;
        },
      ));

      await advanceToEmployees(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      // Pump once for the async submit to resolve; avoid
      // pumpAndSettle which would try to render MainDashboardScreen
      // (see "registro exitoso guarda JWT..." for the rationale).
      await tester.pump();

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['owner']['name'], isNotEmpty);
      expect(capturedPayload!['owner']['phone'], equals('3101234567'));
      expect(capturedPayload!['business']['name'], equals('Tienda Don Pedro'));
      expect(capturedPayload!['business']['type'], equals('tienda_barrio'));
      expect(
        capturedPayload!['business']['types'],
        contains('tienda_barrio'),
      );
      expect(capturedPayload!['config']['sale_types'], isNotEmpty);
    });

    testWidgets(
        'registro exitoso guarda JWT y deja al controller en estado success',
        (tester) async {
      String? savedToken;
      late OnboardingStepperController ctrl;

      await tester.pumpWidget(buildTestWidget(
        apiCall: (_) async => _successResponse,
        saveSession: (data) async {
          savedToken = data['token'] as String?;
        },
      ));
      ctrl = tester
          .element(find.byType(OnboardingStepper))
          .read<OnboardingStepperController>();

      await advanceToEmployees(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      // Don't pumpAndSettle — the stepper pushes MainDashboardScreen
      // which pulls in SyncService/RoleManager providers that aren't
      // wired in this isolated test tree. Pump a single frame so the
      // status-change listener fires and we can observe the side
      // effects we care about: saveSession was called + status is
      // success. Dashboard rendering is covered by the Flow C test.
      await tester.pump();

      expect(savedToken, equals('mock-jwt-token'));
      expect(ctrl.status, equals(StepperStatus.success));
    });

    testWidgets('error del backend muestra mensaje de error en pantalla',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        apiCall: (_) async => throw Exception('409 Conflict'),
      ));

      await advanceToEmployees(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      await tester.pumpAndSettle();

      // Submit failed — we stay on step_employees, not on the dashboard.
      expect(find.byType(MainDashboardScreen), findsNothing);
      expect(find.byKey(const Key('step_employees')), findsOneWidget);
    });
  });
}
