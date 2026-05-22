// Spec: specs/032-email-saliente/spec.md
//
// T-03 — Widget test del TextField "Email (opcional)" en el formulario
// de cliente del flujo de fiar (`CustomerFormScreen`).
//
// Cobertura:
//   - El campo Email existe y es opcional.
//   - Un email con formato inválido muestra el error "Correo inválido".
//   - Un email vacío NO produce error de email (es opcional — AC-07).
//   - Un email con formato válido NO produce error de email.
//
// El formulario corre `Form.validate()` antes de tocar la base de
// datos; al dejar el nombre/teléfono vacíos la validación global falla
// y `createCustomer` nunca se invoca — el test no necesita una DB real.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/fiar/customer_form_screen.dart';
import 'package:vendia_pos/screens/fiar/fiar_controller.dart';
import 'package:vendia_pos/database/database_service.dart';
import 'package:vendia_pos/database/sync/sync_service.dart';
import 'package:vendia_pos/database/sync/connectivity_monitor.dart';
import 'package:vendia_pos/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  /// Controlador real. Es seguro para estas pruebas: dejan nombre y
  /// teléfono vacíos, así `Form.validate()` falla y `createCustomer`
  /// (única ruta que toca DB / sync) nunca se invoca.
  FiarController buildController() {
    final db = DatabaseService.instance;
    final sync = SyncService(
      db: db,
      connectivity: ConnectivityMonitor(),
      auth: AuthService(),
    );
    return FiarController(db, sync);
  }

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CustomerFormScreen(ctrl: buildController())),
    );
  }

  group('CustomerFormScreen — campo Email (F032)', () {
    testWidgets('muestra el campo Email opcional', (tester) async {
      await pumpForm(tester);
      expect(find.byKey(const Key('customer_email_field')), findsOneWidget);
      expect(find.text('Email (opcional)'), findsOneWidget);
    });

    testWidgets('email con formato inválido muestra error', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.byKey(const Key('customer_email_field')),
        'abc',
      );
      // Disparar la validación del formulario.
      await tester.tap(find.text('Guardar cliente'));
      await tester.pumpAndSettle();

      expect(find.text('Correo inválido'), findsOneWidget);
    });

    testWidgets('email "abc@" (incompleto) muestra error', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.byKey(const Key('customer_email_field')),
        'abc@',
      );
      await tester.tap(find.text('Guardar cliente'));
      await tester.pumpAndSettle();

      expect(find.text('Correo inválido'), findsOneWidget);
    });

    testWidgets('email "@xyz.com" (sin parte local) muestra error',
        (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.byKey(const Key('customer_email_field')),
        '@xyz.com',
      );
      await tester.tap(find.text('Guardar cliente'));
      await tester.pumpAndSettle();

      expect(find.text('Correo inválido'), findsOneWidget);
    });

    testWidgets('email vacío NO muestra error de email (opcional)',
        (tester) async {
      await pumpForm(tester);

      // No se escribe nada en el campo email.
      await tester.tap(find.text('Guardar cliente'));
      await tester.pumpAndSettle();

      // La validación global falla por nombre/teléfono, pero el campo
      // email no aporta error porque vacío es válido.
      expect(find.text('Correo inválido'), findsNothing);
    });

    testWidgets('email con formato válido NO muestra error de email',
        (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.byKey(const Key('customer_email_field')),
        'cliente@correo.com',
      );
      await tester.tap(find.text('Guardar cliente'));
      await tester.pumpAndSettle();

      expect(find.text('Correo inválido'), findsNothing);
    });
  });
}
