// Spec: specs/024-captcha-registro-login/spec.md
//
// T-13 — Tests del CAPTCHA en la pantalla de login (F024).
//
// Cubre:
//   AC-04: botón "Entrar" deshabilitado sin token; habilitado con token.
//   AC-06: si el backend responde con CaptchaFailedException, el widget
//          se resetea (token se limpia) para que el usuario resuelva uno nuevo.
//   FR-10: si no hay site key (build sin dart-define), el botón queda
//          habilitado sin captcha (comportamiento idéntico al previo a F024).
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/auth/login_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/turnstile_captcha.dart';

// ── Fake ApiService ────────────────────────────────────────────────────────────

class _FakeApi extends ApiService {
  _FakeApi({this.loginResult}) : super(AuthService());

  /// Cuando es null, lanza [CaptchaFailedException] (simula 400 captcha).
  final Map<String, dynamic>? loginResult;
  String? capturedCaptchaToken;

  @override
  Future<Map<String, dynamic>> loginWithCaptcha({
    required String phone,
    required String password,
    String? captchaToken,
  }) async {
    capturedCaptchaToken = captchaToken;
    if (loginResult == null) {
      throw const CaptchaFailedException();
    }
    return loginResult!;
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Placeholder que reemplaza al WebView real de Turnstile en tests.
Widget _stubTurnstile(TurnstileCaptchaState _) =>
    const SizedBox(key: Key('stub_turnstile'), width: 300, height: 65);

Future<void> _pumpLogin(
  WidgetTester tester,
  _FakeApi api, {
  String siteKeyOverride = '',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LoginScreen(
        apiOverride: api,
        captchaSiteKeyOverride: siteKeyOverride,
        captchaWidgetBuilder: _stubTurnstile,
      ),
    ),
  );
  await tester.pump();
}

/// Encuentra el botón "Entrar" por texto o por key.
Finder _findLoginButton() => find.byKey(const Key('btn_login'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('Login screen — CAPTCHA deshabilitado (FR-10)', () {
    testWidgets(
        'sin site key el botón "Entrar" está habilitado sin necesitar token',
        (tester) async {
      final api = _FakeApi(loginResult: {
        'token': 'mock-token',
        'tenant_id': 1,
        'owner_name': 'Test',
        'business_name': 'Tienda',
      });

      // siteKeyOverride vacío → kill-switch activo
      await _pumpLogin(tester, api, siteKeyOverride: '');

      final btn = tester.widget<InkWell>(
        find.descendant(
          of: _findLoginButton(),
          matching: find.byType(InkWell),
        ),
      );
      // onTap no debe ser null (botón habilitado)
      expect(btn.onTap, isNotNull);
    });
  });

  group('Login screen — CAPTCHA habilitado', () {
    testWidgets('botón "Entrar" deshabilitado hasta recibir token de captcha',
        (tester) async {
      final api = _FakeApi(loginResult: {
        'token': 'mock-token',
        'tenant_id': 1,
        'owner_name': 'Test',
        'business_name': 'Tienda',
      });

      await _pumpLogin(
        tester,
        api,
        siteKeyOverride: '1x00000000000000000000AA',
      );

      // Sin token de captcha, el botón debe estar deshabilitado.
      final btn = tester.widget<InkWell>(
        find.descendant(
          of: _findLoginButton(),
          matching: find.byType(InkWell),
        ),
      );
      expect(btn.onTap, isNull,
          reason: 'Botón debe estar deshabilitado sin token de captcha');
    });

    testWidgets(
        'botón "Entrar" se habilita al recibir token del widget captcha',
        (tester) async {
      final api = _FakeApi(loginResult: {
        'token': 'mock-token',
        'tenant_id': 1,
        'owner_name': 'Test',
        'business_name': 'Tienda',
      });

      await _pumpLogin(
        tester,
        api,
        siteKeyOverride: '1x00000000000000000000AA',
      );

      // Simular recepción de token desde el widget captcha.
      final captchaState =
          tester.state<TurnstileCaptchaState>(find.byType(TurnstileCaptcha));
      captchaState.simulateTokenReceived('tok_test_xyz');
      await tester.pump();

      final btn = tester.widget<InkWell>(
        find.descendant(
          of: _findLoginButton(),
          matching: find.byType(InkWell),
        ),
      );
      expect(btn.onTap, isNotNull,
          reason: 'Botón debe estar habilitado después de recibir token');
    });

    testWidgets(
        'al recibir CaptchaFailedException del backend, el captcha se resetea (AC-06)',
        (tester) async {
      // Api que lanza CaptchaFailedException (simula 400 captcha del backend)
      final api = _FakeApi(loginResult: null);

      await _pumpLogin(
        tester,
        api,
        siteKeyOverride: '1x00000000000000000000AA',
      );

      // Recibir token primero para habilitar el botón.
      final captchaState =
          tester.state<TurnstileCaptchaState>(find.byType(TurnstileCaptcha));
      captchaState.simulateTokenReceived('tok_test_abc');
      await tester.pump();

      // Verificar botón habilitado.
      expect(
        tester
            .widget<InkWell>(
              find.descendant(
                of: _findLoginButton(),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNotNull,
      );

      // Llenar campos obligatorios para pasar la validación del formulario.
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Ej: 310 000 0000',
        ),
        '3101234567',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '• • • •',
        ),
        '1234',
      );
      await tester.pump();

      // Desplazar hasta el botón para que sea tappable.
      await tester.ensureVisible(_findLoginButton());
      await tester.pump();

      // Tap en entrar → ApiService lanza CaptchaFailedException.
      await tester.tap(_findLoginButton(), warnIfMissed: false);
      // Pump suficiente para que el Future de login se resuelva.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // El token del captcha debe haberse limpiado (reset).
      expect(captchaState.currentToken, isNull,
          reason: 'El captcha debe resetearse cuando el backend rechaza el token');
    });
  });
}
