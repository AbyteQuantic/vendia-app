// Spec: specs/085-vender-por-voz/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/product.dart';
import 'package:vendia_pos/screens/pos/voice/product_resolver.dart';
import 'package:vendia_pos/screens/pos/voice/voice_command.dart';
import 'package:vendia_pos/screens/pos/voice/voice_order_controller.dart';

Product p(String name, {double price = 1000, bool avail = true, String uuid = ''}) =>
    Product(
      id: name.hashCode,
      uuid: uuid.isEmpty ? name : uuid,
      name: name,
      price: price,
      stock: 10,
      isAvailable: avail,
    );

void main() {
  const resolver = ProductResolver();

  group('ProductResolver', () {
    final catalog = [
      p('Águila Light botella 350 ml', uuid: 'aguila'),
      p('Agua Cristal 600 ml', uuid: 'agua'),
      p('Cerveza Poker lata', uuid: 'poker'),
      p('Pan tajado', uuid: 'pan', price: 0), // sin precio → excluido
    ];

    test('match difuso ignora tildes y case', () {
      final r = resolver.resolve('aguila', catalog);
      expect(r.status, ResolveStatus.matched);
      expect(r.product!.uuid, 'aguila');
    });

    test('"agua" resuelve a Agua Cristal por contains', () {
      final r = resolver.resolve('agua', catalog);
      expect(r.status, ResolveStatus.matched);
      expect(r.product!.uuid, 'agua');
    });

    test('producto sin precio queda excluido (no vendible)', () {
      final r = resolver.resolve('pan tajado', catalog);
      expect(r.status, ResolveStatus.notFound);
    });

    test('genérico ambiguo NO auto-selecciona', () {
      final multi = [
        p('Gaseosa Cola 350', uuid: 'c1'),
        p('Gaseosa Cola 1.5 L', uuid: 'c2'),
      ];
      final r = resolver.resolve('gaseosa cola', multi);
      expect(r.status, ResolveStatus.ambiguous);
      expect(r.candidates.length, 2);
    });

    test('inexistente → notFound (no inventa)', () {
      final r = resolver.resolve('helado de mango', catalog);
      expect(r.status, ResolveStatus.notFound);
      expect(r.product, isNull);
    });
  });

  group('VoiceOrderResult.fromJson (defensivo)', () {
    test('parsea comandos válidos y descarta acción desconocida', () {
      final res = VoiceOrderResult.fromJson({
        'commands': [
          {'action': 'agregar', 'item': 'aguila', 'quantity': 2, 'raw': 'dos aguilas'},
          {'action': 'hackear', 'item': 'x', 'raw': 'x'},
          {'action': 'quitar', 'item': 'gaseosa', 'quantity': null, 'raw': 'quite'},
        ],
        'transcript': 't',
      });
      expect(res.commands.length, 2);
      expect(res.commands[0].action, VoiceAction.agregar);
      expect(res.commands[0].quantity, 2);
      expect(res.commands[1].action, VoiceAction.quitar);
      expect(res.commands[1].quantity, isNull);
    });

    test('JSON raro → degraded sin lanzar', () {
      expect(VoiceOrderResult.fromJson('no soy map').degraded, isTrue);
      expect(VoiceOrderResult.fromJson(null).degraded, isTrue);
    });

    test('target mesa se parsea', () {
      final res = VoiceOrderResult.fromJson({
        'commands': [
          {'action': 'fijar_mesa', 'target': {'type': 'mesa', 'mesa': '3'}, 'raw': 'mesa 3'}
        ]
      });
      expect(res.commands.first.target!.type, VoiceTargetType.mesa);
      expect(res.commands.first.target!.mesa, '3');
    });
  });

  group('buildPreview (puro)', () {
    final catalog = [
      p('Águila Light', uuid: 'aguila'),
      p('Agua Cristal', uuid: 'agua'),
    ];

    test('orden compuesta: destino + líneas resueltas', () {
      final res = VoiceOrderResult.fromJson({
        'commands': [
          {'action': 'fijar_mesa', 'target': {'type': 'mesa', 'mesa': '3'}, 'raw': ''},
          {'action': 'agregar', 'item': 'aguila', 'quantity': 2, 'raw': ''},
          {'action': 'agregar', 'item': 'agua', 'quantity': 1, 'raw': ''},
          {'action': 'quitar', 'item': 'inexistente', 'quantity': null, 'raw': ''},
        ],
      });
      final preview = buildPreview(res, catalog, resolver);
      expect(preview.target!.mesa, '3');
      expect(preview.lines.length, 3);
      expect(preview.lines[0].product!.uuid, 'aguila');
      expect(preview.lines[0].quantity, 2);
      expect(preview.lines[2].status, ResolveStatus.notFound); // inexistente
    });

    test('cobrar/vaciar se marcan como banderas (no líneas)', () {
      final res = VoiceOrderResult.fromJson({
        'commands': [
          {'action': 'vaciar', 'raw': 'borre todo'},
          {'action': 'cobrar', 'raw': 'cobrele'},
        ],
      });
      final preview = buildPreview(res, catalog, resolver);
      expect(preview.hasVaciar, isTrue);
      expect(preview.hasCobrar, isTrue);
      expect(preview.lines, isEmpty);
    });
  });
}
