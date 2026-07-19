// Spec: specs/106-onboarding-conversacional-agente/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/onboarding/vendi/type_fallback_screen.dart';

// Ancho real de gama baja (360dp — el riesgo de overflow es horizontal);
// alto generoso para que el ListView materialice todo sin coreografía de
// scroll en el test.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'multi-selección de tipos + submit llama agentFallback y completa (AC-10)',
      (tester) async {
    List<String>? sentTypes;
    Map<String, bool>? sentAttrs;
    var completed = false;

    await _pump(
      tester,
      TypeFallbackScreen(
        sessionId: 's-1',
        onCompleted: () => completed = true,
        fallbackCallOverride: (
            {sessionId, businessName, required types, attrs = const {}}) async {
          sentTypes = types;
          sentAttrs = attrs;
          return {'onboarding_completed': true};
        },
      ),
    );

    // CTA deshabilitado sin selección.
    final cta = find.byKey(const Key('fallback_submit'));
    expect(tester.widget<FilledButton>(cta).onPressed, isNull);

    // Multi-selección: tienda + peluquería (negocio mixto, AC-03).
    await tester.tap(find.text('Tienda de Barrio'));
    await tester.pump();
    await tester.tap(find.text('Peluquería / Barbería'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('fallback_attr_fiado')));
    await tester.pump();

    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentTypes, containsAll(['peluqueria_barberia', 'tienda_barrio']));
    expect(sentAttrs?['fiado'], isTrue);
    expect(completed, isTrue);
  });

  testWidgets('error del backend muestra mensaje y no navega', (tester) async {
    var completed = false;
    await _pump(
      tester,
      TypeFallbackScreen(
        onCompleted: () => completed = true,
        fallbackCallOverride: (
            {sessionId, businessName, required types, attrs = const {}}) async {
          return {'degraded': true, 'reason': 'network'};
        },
      ),
    );

    await tester.tap(find.text('Tienda de Barrio'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fallback_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(completed, isFalse);
    expect(find.textContaining('conexión'), findsOneWidget);
  });
}
