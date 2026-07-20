// Spec: specs/106-onboarding-conversacional-agente/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vendia_pos/screens/onboarding/vendi/vendi_chat_controller.dart';

Map<String, dynamic> _turnOk({
  String sessionId = 's-1',
  String phase = 'ask_name',
  List<String> say = const ['¡Hola! Soy Vendi'],
  List<Map<String, dynamic>> chips = const [],
  bool done = false,
}) {
  return {
    'session_id': sessionId,
    'phase': phase,
    'say': say,
    'chips': chips,
    'profile': {'types': [], 'attrs': {}, 'age18': false},
    'done': done,
    'degraded': false,
    'offer_fallback': false,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('start emite el saludo y persiste el session_id (AC-11)', () async {
    String? sentSession;
    final c = VendiChatController(
      turnCall: ({sessionId, text, chip, kind, restart}) async {
        sentSession = sessionId;
        return _turnOk();
      },
      confirmCall: (_) async => {},
      persist: true,
    );
    await c.start();

    expect(sentSession, isNull, reason: 'primer contacto: sin session previa');
    expect(c.sessionId, 's-1');
    expect(c.messages, isNotEmpty);
    expect(c.messages.last.role, VendiRole.assistant);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(VendiChatController.prefsKey), 's-1');
  });

  test('start retoma la sesión guardada (AC-11)', () async {
    SharedPreferences.setMockInitialValues(
        {VendiChatController.prefsKey: 's-guardada'});
    String? sentSession;
    final c = VendiChatController(
      turnCall: ({sessionId, text, chip, kind, restart}) async {
        sentSession = sessionId;
        return _turnOk(sessionId: 's-guardada', phase: 'follow_ups');
      },
      confirmCall: (_) async => {},
      persist: true,
    );
    await c.start();
    expect(sentSession, 's-guardada');
    expect(c.phase, 'follow_ups');
  });

  test('turno feliz actualiza mensajes, chips y perfil', () async {
    final c = VendiChatController(
      turnCall: ({sessionId, text, chip, kind, restart}) async {
        if (text == null) return _turnOk();
        return {
          ..._turnOk(phase: 'confirm_types', say: ['Entendido: tienda y licores']),
          'chips': [
            {'id': 'yes', 'label': 'Sí, así es'},
            {'id': 'no', 'label': 'Falta algo'},
          ],
          'profile': {
            'types': [
              {'key': 'tienda_barrio', 'label': 'tienda de barrio', 'primary': true},
              {'key': 'bar', 'label': 'venta de licores / bar', 'primary': false},
            ],
            'attrs': {},
            'age18': true,
          },
        };
      },
      confirmCall: (_) async => {},
      persist: false,
    );
    await c.start();
    await c.sendText('tengo una tienda y vendo cerveza');

    expect(c.messages.any((m) => m.role == VendiRole.user), isTrue);
    expect(c.chips.length, 2);
    expect(c.profileTypes.length, 2);
    expect(c.phase, 'confirm_types');
  });

  test('degraded expone el fallback y no rompe (AC-10)', () async {
    var first = true;
    final c = VendiChatController(
      turnCall: ({sessionId, text, chip, kind, restart}) async {
        if (first) {
          first = false;
          return _turnOk();
        }
        return {'degraded': true, 'reason': 'network', 'offer_fallback': true, 'say': <String>[]};
      },
      confirmCall: (_) async => {},
      persist: false,
    );
    await c.start();
    await c.sendText('hola');
    expect(c.degraded, isTrue);
    expect(c.offerFallback, isTrue);
  });

  test('envío deshabilitado con turno en vuelo (doble-tap)', () async {
    var calls = 0;
    final c = VendiChatController(
      turnCall: ({sessionId, text, chip, kind, restart}) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _turnOk();
      },
      confirmCall: (_) async => {},
      persist: false,
    );
    final f1 = c.start();
    expect(c.busy, isTrue);
    // Segundo envío mientras hay turno en vuelo → ignorado.
    await c.sendText('doble tap');
    await f1;
    expect(calls, 1);
  });

  test('chip confirm llama al endpoint de confirmación y marca done', () async {
    var confirmed = '';
    final c = VendiChatController(
      turnCall: ({sessionId, text, chip, kind, restart}) async => _turnOk(phase: 'propose'),
      confirmCall: (sessionId) async {
        confirmed = sessionId;
        return {'onboarding_completed': true};
      },
      persist: false,
    );
    await c.start();
    await c.tapChip('confirm', 'Sí, crear mi tienda 🚀');
    expect(confirmed, 's-1');
    expect(c.done, isTrue);
  });
}
