// Spec: specs/106-onboarding-conversacional-agente/spec.md (Adenda A)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_controller.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_screen.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_orb.dart';

VendiChatController _controller({
  Duration delay = Duration.zero,
  Map<String, dynamic>? secondResponse,
}) {
  var first = true;
  return VendiChatController(
    persist: false,
    turnCall: ({sessionId, text, chip, kind, restart}) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (first) {
        first = false;
        return {
          'session_id': 's-1',
          'phase': 'ask_name',
          'say': ['¿Cómo se llama su negocio?'],
          'chips': [],
          'profile': {'types': [], 'attrs': {}},
          'done': false,
        };
      }
      return secondResponse ??
          {
            'session_id': 's-1',
            'phase': 'follow_ups',
            'pending_key': 'mesas',
            'say': ['¿Sus clientes consumen en mesas?'],
            'chips': [
              {'id': 'yes', 'label': 'Sí'},
              {'id': 'no', 'label': 'No'},
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
  await tester.pumpWidget(MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MaterialApp(
      home: VendiChatScreen(
        controllerOverride: c,
        onCompleted: () {},
        onFallback: () {},
      ),
    ),
  ));
}

VendiOrb _orb(WidgetTester tester) =>
    tester.widget<VendiOrb>(find.byKey(const Key('vendi_avatar')));

void main() {
  test('controller expone pending_key del turn (Adenda A)', () async {
    final c = _controller();
    await c.start();
    await c.sendText('Mi tienda');
    expect(c.pendingKey, 'mesas');
  });

  testWidgets('pregunta en reposo → mood asking (AC-A4)', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    await tester.pumpAndSettle();
    expect(_orb(tester).mood, VendiOrbMood.asking);
  });

  testWidgets('mientras interpreta → mood thinking (AC-A4)', (tester) async {
    final c = _controller(delay: const Duration(milliseconds: 300));
    await _pump(tester, c);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_orb(tester).mood, VendiOrbMood.thinking);
    await tester.pumpAndSettle();
  });

  testWidgets('propuesta visible → mood explaining (AC-A4)', (tester) async {
    final c = _controller(secondResponse: {
      'session_id': 's-1',
      'phase': 'propose',
      'say': ['Le dejo lista su tienda con esto:'],
      'chips': [
        {'id': 'confirm', 'label': 'Confirmar'},
      ],
      'profile': {'types': [], 'attrs': {}},
      'proposal': {
        'grid': ['Ventas', 'Inventario'],
        'reel': ['Catálogo online'],
      },
      'done': false,
    });
    await _pump(tester, c);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vendi_input')), 'tienda');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();
    expect(_orb(tester).mood, VendiOrbMood.explaining);
  });

  testWidgets('terminado → mood settled (AC-A4)', (tester) async {
    final c = _controller(secondResponse: {
      'session_id': 's-1',
      'phase': 'done',
      'say': ['¡Listo! Su tienda quedó configurada. 💙'],
      'chips': [],
      'profile': {'types': [], 'attrs': {}},
      'done': true,
    });
    await _pump(tester, c);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vendi_input')), 'tienda');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();
    expect(_orb(tester).mood, VendiOrbMood.settled);
    // Deja disparar el Future.delayed del cierre (onCompleted) antes de
    // desmontar — sin esto el binding acusa un timer pendiente.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('follow-up mesas → forma temática mesa + beat avanza (Adenda A)',
      (tester) async {
    final c = _controller();
    await _pump(tester, c);
    await tester.pumpAndSettle();
    final beat0 = _orb(tester).beat;
    await tester.enterText(find.byKey(const Key('vendi_input')), 'Mi tienda');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();
    expect(_orb(tester).shape, VendiOrbShape.mesa);
    expect(_orb(tester).beat, greaterThan(beat0),
        reason: 'cada mensaje nuevo puntúa con un latido');
  });

  testWidgets('el diálogo tiene desvanecido superior (AC-A5)', (tester) async {
    final c = _controller();
    await _pump(tester, c);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendi_dialogue_fade')), findsOneWidget);
  });

  testWidgets('VendiOrb construye con cada mood sin errores', (tester) async {
    for (final mood in VendiOrbMood.values) {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: VendiOrb(
              shape: VendiOrbShape.palomilla, mood: mood, size: 100),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: 'mood $mood');
    }
  });
}
