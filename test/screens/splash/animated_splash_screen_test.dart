// Spec: specs/087-splash-loader-animado/spec.md
//
// Regresión bug prod 2026-07-08 (web): la app quedaba EN BLANCO en el splash
// y solo avanzaba al tocar la pantalla. El safeguard de los 7s exigía
// `_authResolved`: con la auth colgada NUNCA navegaba. Ahora el safeguard
// entra SIEMPRE — si la auth no resolvió, espera una gracia corta (2s) y por
// defecto va a Login (fail-safe). La navegación por onDone (animación
// terminada o fail-safe de assets) sigue funcionando sin esperar el safeguard.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/auth/login_screen.dart';
import 'package:vendia_pos/screens/splash/animated_splash_screen.dart';
import 'package:vendia_pos/theme/app_theme.dart';

const SplashSession _noSession =
    (hasSession: false, ownerName: '', businessName: '');

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets(
      'con auth resuelta, la animación (u onDone del fail-safe de assets) '
      'navega sola ANTES del safeguard de 7s', (tester) async {
    await tester.pumpWidget(_wrap(
      AnimatedSplashScreen(sessionResolver: () async => _noSession),
    ));
    await tester.pump();

    // Avanza hasta 6s en pasos cortos: la animación completa (~2.65s) o el
    // fail-safe de assets (~3.3s) disparan onDone — siempre < 7s.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(LoginScreen), findsOneWidget);

    // Termina la transición para que el splash se desmonte (cancela timers).
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets(
      'safeguard con auth tardía: a los 7s espera la gracia y navega '
      'apenas la auth resuelve', (tester) async {
    final auth = Completer<SplashSession>();
    await tester.pumpWidget(_wrap(
      AnimatedSplashScreen(sessionResolver: () => auth.future),
    ));
    await tester.pump();

    // A los 7.5s el safeguard ya corrió pero la auth sigue pendiente: aún
    // dentro de la gracia (2s) no se navega.
    await tester.pump(const Duration(milliseconds: 7500));
    expect(find.byType(LoginScreen), findsNothing);

    // La auth resuelve durante la gracia → navega de inmediato (los pumps
    // extra solo avanzan la transición de la ruta ya empujada).
    auth.complete(_noSession);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoginScreen), findsOneWidget);

    // Flush: timer de gracia (9s) + transición de ruta (desmonta el splash).
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'safeguard con auth COLGADA (nunca resuelve): entra a Login por '
      'defecto a los ~9s (7s + 2s de gracia)', (tester) async {
    final never = Completer<SplashSession>(); // jamás se completa
    await tester.pumpWidget(_wrap(
      AnimatedSplashScreen(sessionResolver: () => never.future),
    ));
    await tester.pump();

    // A los 8.5s: safeguard corrió (7s) pero la gracia no venció — sin navegar.
    await tester.pump(const Duration(milliseconds: 8500));
    expect(find.byType(LoginScreen), findsNothing);

    // Vence la gracia (9s) → default sin sesión → Login. Nunca se queda
    // en blanco esperando un toque del usuario (bug prod 2026-07-08).
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    // Termina la transición para que el splash se desmonte (cancela timers).
    await tester.pump(const Duration(seconds: 1));
  });
}
