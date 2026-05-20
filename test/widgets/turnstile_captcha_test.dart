// Spec: specs/024-captcha-registro-login/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/turnstile_captcha.dart';

/// Tests para el widget TurnstileCaptcha (T-11).
///
/// Estrategia de aislamiento: [TurnstileCaptcha] acepta un
/// [turnstileWidgetBuilder] opcional (solo para tests) que reemplaza al
/// [CloudflareTurnstile] real — así no se monta ningún InAppWebView en la
/// VM de tests (que no tiene AndroidSDK ni WebView platform registrada).
///
/// Para las rutas que dependen de callbacks (onToken, onError, reset)
/// accedemos al state vía [TurnstileCaptchaState] y llamamos a los
/// métodos simulateTokenReceived / simulateError directamente.

/// Widget placeholder que ocupa el lugar del Turnstile real en tests.
Widget _dummyTurnstile(TurnstileCaptchaState _) =>
    const SizedBox(key: Key('dummy_turnstile'), width: 300, height: 65);

/// Helper que monta un [TurnstileCaptcha] con la clave dada y un builder stub.
Widget _buildCaptcha({
  required String siteKey,
  required void Function(String) onToken,
  required void Function(String) onError,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TurnstileCaptcha(
        siteKeyOverride: siteKey,
        turnstileWidgetBuilder: _dummyTurnstile,
        onToken: onToken,
        onError: onError,
      ),
    ),
  );
}

void main() {
  group('TurnstileCaptcha — sin site key (FR-10)', () {
    testWidgets(
        'devuelve SizedBox.shrink y no renderiza nada cuando el site key es vacío',
        (WidgetTester tester) async {
      String? receivedToken;
      String? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TurnstileCaptcha(
              siteKeyOverride: '',
              onToken: (t) => receivedToken = t,
              onError: (e) => receivedError = e,
            ),
          ),
        ),
      );

      // Con site key vacío el widget devuelve SizedBox.shrink.
      expect(find.byType(SizedBox), findsOneWidget);
      // No debe haber un loader del captcha.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // No deben haberse disparado callbacks.
      expect(receivedToken, isNull);
      expect(receivedError, isNull);
    });
  });

  group('TurnstileCaptcha — con site key presente', () {
    testWidgets('monta el widget y muestra el loader inicial',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildCaptcha(
          siteKey: '1x00000000000000000000AA',
          onToken: (_) {},
          onError: (_) {},
        ),
      );

      // El widget existe y no lanzó excepciones durante el build.
      expect(find.byType(TurnstileCaptcha), findsOneWidget);
      // Antes de recibir token, muestra el loader.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // El placeholder del turnstile está montado.
      expect(find.byKey(const Key('dummy_turnstile')), findsOneWidget);
    });

    testWidgets('dispara onToken cuando el state notifica un token',
        (WidgetTester tester) async {
      String? capturedToken;

      await tester.pumpWidget(
        _buildCaptcha(
          siteKey: '1x00000000000000000000AA',
          onToken: (t) => capturedToken = t,
          onError: (_) {},
        ),
      );

      final captchaState = tester
          .state<TurnstileCaptchaState>(find.byType(TurnstileCaptcha));
      captchaState.simulateTokenReceived('tok_test_abc123');

      await tester.pump();

      expect(capturedToken, equals('tok_test_abc123'));
      // Loader desaparece tras recibir token.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('dispara onError y muestra botón Reintentar ante un error',
        (WidgetTester tester) async {
      String? capturedError;

      await tester.pumpWidget(
        _buildCaptcha(
          siteKey: '1x00000000000000000000AA',
          onToken: (_) {},
          onError: (e) => capturedError = e,
        ),
      );

      final captchaState = tester
          .state<TurnstileCaptchaState>(find.byType(TurnstileCaptcha));
      captchaState.simulateError('Error de verificación');

      await tester.pump();

      expect(capturedError, equals('Error de verificación'));
      // Botón de reintentar aparece.
      expect(find.text('Reintentar verificación'), findsOneWidget);
      // Loader desaparece.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('reset() limpia el token interno y vuelve al estado inicial',
        (WidgetTester tester) async {
      String? capturedToken;

      await tester.pumpWidget(
        _buildCaptcha(
          siteKey: '1x00000000000000000000AA',
          onToken: (t) => capturedToken = t,
          onError: (_) {},
        ),
      );

      final captchaState = tester
          .state<TurnstileCaptchaState>(find.byType(TurnstileCaptcha));

      // Simular token recibido.
      captchaState.simulateTokenReceived('tok_original');
      await tester.pump();
      expect(capturedToken, equals('tok_original'));
      expect(captchaState.currentToken, equals('tok_original'));

      // Resetear el widget.
      captchaState.reset();
      await tester.pump();

      // El token interno queda limpio.
      expect(captchaState.currentToken, isNull);
      // El loader vuelve (esperando nuevo token).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
        'tapping Reintentar tras error llama a reset y vuelve al estado de carga',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildCaptcha(
          siteKey: '1x00000000000000000000AA',
          onToken: (_) {},
          onError: (_) {},
        ),
      );

      final captchaState = tester
          .state<TurnstileCaptchaState>(find.byType(TurnstileCaptcha));
      captchaState.simulateError('Falló la verificación');
      await tester.pump();

      // Botón Reintentar visible.
      expect(find.text('Reintentar verificación'), findsOneWidget);

      // Tap en reintentar.
      await tester.tap(find.text('Reintentar verificación'));
      await tester.pump();

      // El estado de error se limpia y vuelve el loader.
      expect(find.text('Reintentar verificación'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
