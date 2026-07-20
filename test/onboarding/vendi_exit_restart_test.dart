// Spec: specs/106-onboarding-conversacional-agente/spec.md (Adenda A.3)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_controller.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_screen.dart';

VendiChatController _controller({List<bool?>? restartLog}) {
  var calls = 0;
  return VendiChatController(
    persist: false,
    turnCall: ({sessionId, text, chip, kind, restart}) async {
      calls++;
      restartLog?.add(restart);
      return {
        'session_id': restart == true ? 's-nueva' : 's-$calls',
        'phase': 'ask_name',
        'say': ['¿Cómo se llama su negocio?'],
        'chips': [],
        'profile': {'types': [], 'attrs': {}},
        'done': false,
      };
    },
    confirmCall: (_) async => {'onboarding_completed': true},
  );
}

Future<void> _pump(WidgetTester tester, VendiChatController c,
    {VoidCallback? onFallback}) async {
  tester.view.physicalSize = const Size(360, 690);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MaterialApp(
      home: VendiChatScreen(
        controllerOverride: c,
        onCompleted: () {},
        onFallback: onFallback,
      ),
    ),
  ));
}

void main() {
  test('restart limpia estado y manda restart:true (FR-A6)', () async {
    final log = <bool?>[];
    final c = _controller(restartLog: log);
    await c.start();
    await c.sendText('Mi tienda');
    expect(c.messages.length, greaterThan(1));

    await c.restart();
    expect(log.last, isTrue);
    expect(c.sessionId, 's-nueva');
    // Solo el saludo nuevo queda en pantalla.
    expect(c.messages.length, 1);
    expect(c.done, isFalse);
  });

  testWidgets('menú ofrece reiniciar y selección manual (AC-A6)',
      (tester) async {
    var fallback = false;
    final c = _controller();
    await _pump(tester, c, onFallback: () => fallback = true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vendi_menu')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vendi_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendi_menu_restart')), findsOneWidget);
    expect(find.byKey(const Key('vendi_menu_fallback')), findsOneWidget);

    await tester.tap(find.byKey(const Key('vendi_menu_fallback')));
    await tester.pumpAndSettle();
    expect(fallback, isTrue);
  });

  testWidgets('reiniciar desde el menú vuelve al saludo (AC-A6)',
      (tester) async {
    final log = <bool?>[];
    final c = _controller(restartLog: log);
    await _pump(tester, c);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vendi_input')), 'Mi tienda');
    await tester.tap(find.byKey(const Key('vendi_send')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vendi_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vendi_menu_restart')));
    await tester.pumpAndSettle();

    expect(log.last, isTrue);
    expect(c.messages.length, 1);
  });

  testWidgets('modo assist: flecha de regreso cierra el chat (AC-A7)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = _controller();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VendiChatScreen(
                    controllerOverride: c,
                    kind: 'assist',
                    onCompleted: () {},
                  ),
                )),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('abrir')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendi_back')), findsOneWidget);
    // En assist no aplica la selección manual de tipos.
    await tester.tap(find.byKey(const Key('vendi_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendi_menu_fallback')), findsNothing);
    await tester.tap(find.byKey(const Key('vendi_menu_restart')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vendi_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendi_avatar')), findsNothing);
  });
}
