import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/screens/dashboard/main_dashboard_screen.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper.dart';
import 'package:vendia_pos/screens/onboarding/onboarding_stepper_controller.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Respuesta simulada exitosa del backend.
final _successResponse = {
  'token': 'mock-jwt-token',
  'tenant_id': 42,
  'owner_name': 'Pedro Martínez',
  'business_name': 'Tienda Don Pedro',
};

/// Construye el widget bajo prueba con servicios inyectables.
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

/// Rellena y avanza el Paso 1 (Propietario).
Future<void> fillAndAdvanceStep1(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('owner_name')), 'Pedro');
  await tester.enterText(find.byKey(const Key('owner_lastname')), 'Martínez');
  await tester.enterText(find.byKey(const Key('owner_phone')), '3101234567');
  await tester.enterText(find.byKey(const Key('owner_pin')), '1234');
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

/// Rellena y avanza el Paso 2 (Tienda).
Future<void> fillAndAdvanceStep2(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('biz_name')), 'Tienda Don Pedro');
  await tester.enterText(find.byKey(const Key('biz_razon')), 'Pedro SAS');
  await tester.enterText(find.byKey(const Key('biz_nit')), '900000001-0');
  await tester.enterText(find.byKey(const Key('biz_address')), 'Calle 12 #34');
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
}

/// Selecciona un tipo de negocio y avanza en el Paso 3 (Configuración).
Future<void> selectAndAdvanceStep3(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('btype_tienda_barrio')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn_next')));
  await tester.pumpAndSettle();
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

      // Al menos un mensaje de error de validación debe aparecer
      final errorFinders = [
        find.text('Ingrese su nombre'),
        find.text('Ingrese su apellido'),
        find.text('Ingrese su número'),
        find.text('Ingrese su clave'),
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
      await tester.enterText(find.byKey(const Key('owner_pin')), '12'); // corto
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

      // Paso 2 debe estar visible
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

    testWidgets('navega correctamente por los 4 pasos hasta Empleados',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Paso 1 → 2
      await fillAndAdvanceStep1(tester);
      expect(find.byKey(const Key('biz_name')), findsOneWidget);

      // Paso 2 → 3
      await fillAndAdvanceStep2(tester);
      expect(find.byKey(const Key('step_config')), findsOneWidget);

      // Paso 3 → 4
      await selectAndAdvanceStep3(tester);
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
      expect(find.byKey(const Key('biz_address')), findsOneWidget);
    });

    testWidgets('Siguiente sin nombre de negocio muestra error',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);

      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      expect(find.text('Ingrese el nombre de la tienda'), findsOneWidget);
    });
  });

  group('OnboardingStepper — Paso 3: Configuración', () {
    testWidgets('muestra las 4 tarjetas de tipo de negocio', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);

      expect(find.byKey(const Key('btype_tienda_barrio')), findsOneWidget);
      expect(find.byKey(const Key('btype_minimercado')), findsOneWidget);
      expect(find.byKey(const Key('btype_bar')), findsOneWidget);
      expect(find.byKey(const Key('btype_miscelanea')), findsOneWidget);
    });

    testWidgets('Siguiente sin seleccionar tipo de negocio muestra error',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);

      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();

      expect(find.text('Seleccione el tipo de negocio'), findsOneWidget);
    });

    testWidgets('seleccionar una tarjeta la marca como activa', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);

      await tester.tap(find.byKey(const Key('btype_minimercado')));
      await tester.pump();

      final ctrl = tester
          .element(find.byType(OnboardingStepper))
          .read<OnboardingStepperController>();
      expect(ctrl.businessType, equals('minimercado'));
    });
  });

  group('OnboardingStepper — Paso 4: Empleados', () {
    testWidgets('muestra la pregunta de empleados y las 2 opciones',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await selectAndAdvanceStep3(tester);

      expect(find.byKey(const Key('step_employees')), findsOneWidget);
      expect(find.byKey(const Key('emp_yes')), findsOneWidget);
      expect(find.byKey(const Key('emp_no')), findsOneWidget);
    });

    testWidgets('seleccionar NO muestra mensaje de cajero por defecto',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await selectAndAdvanceStep3(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();

      expect(
        find.text('Te asignaremos como el cajero principal por defecto'),
        findsOneWidget,
      );
    });

    testWidgets('muestra botón Finalizar Registro en el Paso 4',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await selectAndAdvanceStep3(tester);

      expect(find.byKey(const Key('btn_submit')), findsOneWidget);
    });
  });

  group('OnboardingStepper — Submit y Navegación', () {
    testWidgets('submit llama al API con el payload correcto', (tester) async {
      Map<String, dynamic>? capturedPayload;

      await tester.pumpWidget(buildTestWidget(
        apiCall: (payload) async {
          capturedPayload = payload;
          return _successResponse;
        },
      ));

      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await selectAndAdvanceStep3(tester);

      // Paso 4: seleccionar NO y enviar
      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      await tester.pumpAndSettle();

      expect(capturedPayload, isNotNull);

      // Verifica estructura del payload
      expect(capturedPayload!['owner']['name'], isNotEmpty);
      expect(capturedPayload!['owner']['phone'], equals('3101234567'));
      expect(capturedPayload!['business']['name'], equals('Tienda Don Pedro'));
      expect(capturedPayload!['business']['type'], equals('tienda_barrio'));
      expect(capturedPayload!['config']['sale_types'], isNotEmpty);
    });

    testWidgets('registro exitoso guarda JWT y navega a MainDashboardScreen',
        (tester) async {
      String? savedToken;

      await tester.pumpWidget(buildTestWidget(
        apiCall: (_) async => _successResponse,
        saveSession: (data) async {
          savedToken = data['token'] as String?;
        },
      ));

      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await selectAndAdvanceStep3(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      await tester.pumpAndSettle();

      // JWT fue guardado
      expect(savedToken, equals('mock-jwt-token'));

      // Navega a MainDashboardScreen
      expect(find.byType(MainDashboardScreen), findsOneWidget);
    });

    testWidgets('error del backend muestra mensaje de error en pantalla',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        apiCall: (_) async => throw Exception('409 Conflict'),
      ));

      await fillAndAdvanceStep1(tester);
      await fillAndAdvanceStep2(tester);
      await selectAndAdvanceStep3(tester);

      await tester.tap(find.byKey(const Key('emp_no')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      await tester.pumpAndSettle();

      // Debe mostrar mensaje de error (no navegar)
      expect(find.byType(MainDashboardScreen), findsNothing);
      expect(find.byKey(const Key('step_employees')), findsOneWidget);
    });
  });
}
