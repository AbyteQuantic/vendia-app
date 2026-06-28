// Spec: specs/085-vender-por-voz/spec.md
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';
import 'package:vendia_pos/screens/pos/voice/voice_order_controller.dart';
import 'package:vendia_pos/services/voice_recorder.dart';

class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({this.grant = true});
  final bool grant;
  @override
  Future<bool> hasPermission({bool request = true}) async => grant;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {}
  @override
  Future<String?> stop() async => 'fake-clip';
  @override
  Future<void> dispose() async {}
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<String> _fakePath() async => 'fake-clip';
Future<RecordedAudio> _fakeAudio(String _) async => RecordedAudio(
      // Tamaño realista (> umbral de "audio diminuto" del controller); el audio
      // real siempre supera el guard. 3 bytes simulaba un clip imposible.
      bytes: Uint8List(2048),
      mimeType: 'audio/wav',
      filename: 'v.wav',
    );

VoiceOrderApi _api(Map<String, dynamic> result) =>
    ({required audioBytes, required mimeType, required filename}) async => result;

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  late CartController cart;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cart = CartController();
  });

  VoiceOrderController make(Map<String, dynamic> apiResult, {bool grant = true}) =>
      VoiceOrderController(
        cart: cart,
        recorder: _FakeRecorder(grant: grant),
        apiCall: _api(apiResult),
        resolvePath: _fakePath,
        readAudio: _fakeAudio,
      );

  test('graba→procesa→preview NO toca el carrito hasta confirmar', () async {
    final c = make({
      'commands': [
        {'action': 'agregar', 'item': 'gaseosa cola', 'quantity': 2, 'raw': ''},
        {'action': 'agregar', 'item': 'agua cristal', 'quantity': 1, 'raw': ''},
      ],
      'transcript': 't',
    });
    await c.startRecording();
    await c.stopAndProcess();

    expect(c.phase, VoicePhase.review);
    expect(c.preview.lines.length, 2);
    // CLAVE: el carrito sigue vacío antes de confirmar.
    expect(cart.activeCart, isEmpty);

    final outcome = c.applyConfirmed();
    expect(outcome.appliedLines, 2);
    expect(cart.activeCart.length, 2);
    final cola = cart.activeCart.firstWhere((i) => i.product.name.contains('Cola'));
    expect(cola.quantity, 2);

    // Idempotente: segunda confirmación no duplica.
    c.applyConfirmed();
    final cola2 = cart.activeCart.firstWhere((i) => i.product.name.contains('Cola'));
    expect(cola2.quantity, 2);
  });

  test('degraded → error y carrito intacto (no rompe la venta)', () async {
    final c = make({'commands': [], 'degraded': true});
    await c.startRecording();
    await c.stopAndProcess();
    expect(c.phase, VoicePhase.error);
    expect(cart.activeCart, isEmpty);
  });

  test('audio diminuto → error claro, NO llama a la IA (no degraded)', () async {
    var apiCalled = false;
    final c = VoiceOrderController(
      cart: cart,
      recorder: _FakeRecorder(grant: true),
      apiCall: ({required audioBytes, required mimeType, required filename}) async {
        apiCalled = true;
        return {'commands': []};
      },
      resolvePath: _fakePath,
      readAudio: (_) async => RecordedAudio(
        bytes: Uint8List.fromList(const [1, 2, 3]), // clip vacío/imposible
        mimeType: 'audio/wav',
        filename: 'v.wav',
      ),
    );
    await c.startRecording();
    await c.stopAndProcess();
    expect(c.phase, VoicePhase.error);
    expect(c.error, contains('escuchar'));
    expect(apiCalled, isFalse); // no malgasta una llamada a Gemini con audio vacío
  });

  test('permiso de micrófono denegado → error accionable', () async {
    final c = make({'commands': []}, grant: false);
    await c.startRecording();
    expect(c.phase, VoicePhase.error);
    expect(c.error, contains('micrófono'));
  });

  test('fijar_cantidad fija el total absoluto (no suma)', () async {
    cart.addProduct(CartController.mockProducts.firstWhere((p) => p.name.contains('Cola')));
    final c = make({
      'commands': [
        {'action': 'fijar_cantidad', 'item': 'gaseosa cola', 'quantity': 5, 'raw': ''},
      ],
    });
    await c.startRecording();
    await c.stopAndProcess();
    c.applyConfirmed();
    final cola = cart.activeCart.firstWhere((i) => i.product.name.contains('Cola'));
    expect(cola.quantity, 5);
  });
}
