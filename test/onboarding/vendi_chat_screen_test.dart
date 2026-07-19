// Spec: specs/106-onboarding-conversacional-agente/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_controller.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_screen.dart';

VendiChatController _controller({
  Duration delay = Duration.zero,
  Map<String, dynamic>? proposeResponse,
}) {
  var first = true;
  return VendiChatController(
    persist: false,
    turnCall: ({sessionId, text, chip}) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (first) {
        first = false;
        return {
          'session_id': 's-1',
          'phase': 'ask_name',
          'say': [
            '¡Hola! 👋 Soy <b>Vendi</b>. Voy a dejar su tienda lista en un par de minutos.',
            'Primero, ¿cómo se llama su negocio?'
          ],
          'chips': [],
          'profile': {'types': [], 'attrs': {}},
          'done': false,
        };
      }
      return proposeResponse ??
          {
            'session_id': 's-1',
            'phase': 'confirm_types',
            'say': ['Entendido: su negocio tiene <b>tienda de barrio</b>. ¿Es correcto?'],
            'chips': [
              {'id': 'yes', 'label': 'Sí, así es'},
              {'id': 'no', 'label': 'Falta algo / no es así'},
            ],
            'profile': {'types': [], 'attrs': {}},
            'done': false,
          };
    },
    confirmCall: (_) async => {'onboarding_completed': true},
  );
}

Future<void> _pump(WidgetTester tester, VendiChatController c) async {
  tester.view.physicalSize = const Size(360, 690);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: VendiChatScreen(
      controllerOverride: c,
      onCompleted: () {},
      onFallback: () {},
    ),
  ));
}

void main() {
  testWidgets('renderiza avatar, saludo, input y sin overflow a 360dp (AC-01)',
      (tester) async {
    final c = _controller();
    await _pump(tester, c);
    await tester.pumpAndSettle();

    expect(find.text('Vendi'), findsOneWidget);
    expect(find.byKey(const Key('vendi_avatar')), findsOneWidget);
    expect(find.byKey(const Key('vendi_input')), findsOneWidget);
    expect(find.byKey(const Key('vendi_send')), findsOneWidget);
    expect(find.textContaining('cómo se llama su negocio', findRichText: true),
        findsOneWidget);
    // El framework falla solo si hay overflow — llegar aquí ya lo verifica.
  });

  testWidgets('muestra indicador escribiendo mientras el turno está en vuelo',
      (tester) async {
    final c = _controller(delay: const Duration(milliseconds: 300));
    await _pump(tester, c);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('vendi_typing')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendi_typing')), findsNothing);
  });

  testWidgets('chips de confirmación visibles y tocables', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('vendi_input')), 'tengo una tienda');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();

    expect(find.text('Sí, así es'), findsOneWidget);
    expect(find.text('Falta algo / no es así'), findsOneWidget);
  });

  testWidgets('propuesta final muestra módulos y CTA de confirmar (AC-01/FR-06)',
      (tester) async {
    final c = _controller(proposeResponse: {
      'session_id': 's-1',
      'phase': 'propose',
      'say': ['¡Listo! 🎉 Así quedaría su tienda.', '¿Creamos su tienda con esta configuración?'],
      'chips': [
        {'id': 'confirm', 'label': 'Sí, crear mi tienda 🚀'},
        {'id': 'adjust', 'label': 'Quiero ajustar algo'},
      ],
      'profile': {'types': [], 'attrs': {}},
      'proposal': {
        'grid': ['Vender', 'Productos', 'Historial', 'Ganancias', 'Cuaderno de fiados'],
        'reel': ['Catálogo online'],
      },
      'done': false,
    });
    await _pump(tester, c);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('vendi_input')), 'una tienda');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();

    expect(find.text('Vender'), findsOneWidget);
    expect(find.text('Cuaderno de fiados'), findsOneWidget);
    expect(find.text('Sí, crear mi tienda 🚀'), findsOneWidget);
  });

  testWidgets('degraded ofrece el camino manual (AC-10)', (tester) async {
    var first = true;
    var fallbackTapped = false;
    final c = VendiChatController(
      persist: false,
      turnCall: ({sessionId, text, chip}) async {
        if (first) {
          first = false;
          return {
            'session_id': 's-1',
            'phase': 'ask_description',
            'say': ['¿Qué vende?'],
            'chips': [],
            'profile': {'types': [], 'attrs': {}},
            'done': false,
          };
        }
        return {'degraded': true, 'reason': 'network', 'offer_fallback': true, 'say': <String>[]};
      },
      confirmCall: (_) async => {},
    );
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: VendiChatScreen(
        controllerOverride: c,
        onCompleted: () {},
        onFallback: () => fallbackTapped = true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('vendi_input')), 'x');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vendi_fallback_cta')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vendi_fallback_cta')));
    expect(fallbackTapped, isTrue);
  });
}
