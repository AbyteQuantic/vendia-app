// Spec: specs/004-idempotencia-venta-login/spec.md
//
// Feature 004 · BUG-7 — Login alfanumérico (T-20).
//
// El campo "Clave de acceso" del login de tenant debe aceptar caracteres
// alfanuméricos, porque `POST /tenant/register` ya permite claves
// alfanuméricas. Un tenant registrado con clave alfanumérica no podía
// entrar a la app porque el campo filtraba solo dígitos.
//
// AC-04: una clave alfanumérica (p. ej. `abc12345`) es aceptada por el campo.
// AC-05: una clave numérica sigue siendo válida (sin regresión).
//
// El campo de PIN de empleado (4 dígitos, inicio de turno) vive en
// `lib/screens/employees/cashier_selector_screen.dart` y NO se toca.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/auth/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // LoginScreen construye ApiService en initState, que lee
    // ApiConfig.baseUrl desde dotenv. Sembramos un payload inline para
    // evitar NotInitializedError — no se toca ningún archivo .env.
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  // Localiza el campo "Clave de acceso" del login de tenant por su label.
  Future<Finder> pumpLoginAndFindPasswordField(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();

    // El campo de clave es el TextFormField que sigue al label
    // "Clave de acceso". Se identifica por su hint de PIN ('• • • •').
    final passwordField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == '• • • •',
    );
    expect(
      passwordField,
      findsOneWidget,
      reason: 'Debe existir exactamente un campo "Clave de acceso".',
    );
    return passwordField;
  }

  group('Login de tenant — campo "Clave de acceso" (Feature 004 / BUG-7)', () {
    testWidgets(
      'AC-04: acepta una clave alfanumérica (abc12345)',
      (tester) async {
        final passwordField = await pumpLoginAndFindPasswordField(tester);

        await tester.enterText(passwordField, 'abc12345');
        await tester.pump();

        final field = tester.widget<TextField>(passwordField);
        expect(
          field.controller?.text,
          'abc12345',
          reason: 'El campo de clave debe conservar letras y dígitos; '
              'el filtro digitsOnly bloqueaba claves alfanuméricas.',
        );
      },
    );

    testWidgets(
      'AC-05: una clave numérica sigue siendo válida (sin regresión)',
      (tester) async {
        final passwordField = await pumpLoginAndFindPasswordField(tester);

        await tester.enterText(passwordField, '12345678');
        await tester.pump();

        final field = tester.widget<TextField>(passwordField);
        expect(
          field.controller?.text,
          '12345678',
          reason: 'Una clave numérica debe seguir funcionando.',
        );
      },
    );

    testWidgets(
      'el teclado del campo de clave es de texto (no numérico)',
      (tester) async {
        final passwordField = await pumpLoginAndFindPasswordField(tester);
        final field = tester.widget<TextField>(passwordField);

        expect(
          field.keyboardType,
          TextInputType.text,
          reason: 'El teclado debe permitir escribir letras.',
        );
      },
    );
  });
}
