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

    // ── Plurales / verbos: "vendo 3 empanadas" debe encontrar "Empanada" ──
    group('plurales y verbos', () {
      final tienda = [
        p('Empanada', uuid: 'emp'),
        p('Empanada de carne', uuid: 'emp-carne'),
        p('Gaseosa Cola 350', uuid: 'gas'),
      ];

      test('plural de una palabra: "empanadas" → Empanada', () {
        final r = resolver.resolve('empanadas', [p('Empanada', uuid: 'emp')]);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'emp');
      });

      test('plural multi-palabra: "empanadas" → Empanada de carne (única)', () {
        final r = resolver.resolve('empanadas', [p('Empanada de carne', uuid: 'x')]);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'x');
      });

      test('verbo colado: "vendo empanadas" → Empanada', () {
        final r = resolver.resolve('vendo empanadas', [p('Empanada', uuid: 'emp')]);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'emp');
      });

      test('reverso: producto plural "Empanadas", hablado "empanada"', () {
        final r = resolver.resolve('empanada', [p('Empanadas', uuid: 'emp')]);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'emp');
      });

      test('plural con "-es": "panes" → Pan tajado', () {
        final r = resolver.resolve('panes', [p('Pan tajado', uuid: 'pan')]);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'pan');
      });

      test('artículos/muletillas se ignoran: "para la gaseosa"', () {
        final r = resolver.resolve('para la gaseosa', [p('Gaseosa Cola 350', uuid: 'gas')]);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'gas');
      });

      // Seguridad: "con gas"/"sin gas" NO se deben colapsar (son productos
      // distintos). El deplural/strip nunca debe borrar palabras de contenido.
      test('"con gas" y "sin gas" siguen siendo distintos', () {
        final aguas = [
          p('Agua con gas', uuid: 'con'),
          p('Agua sin gas', uuid: 'sin'),
        ];
        final r = resolver.resolve('agua con gas', aguas);
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'con');
      });

      test('exacto gana: "empanadas" con Empanada + Empanada de carne → Empanada', () {
        final r = resolver.resolve('empanadas', tienda);
        // "empanadas" → base "empanada" hace match EXACTO con el producto
        // llamado literalmente "Empanada"; no lo vuelve ambiguo el multi-palabra.
        expect(r.status, ResolveStatus.matched);
        expect(r.product!.uuid, 'emp');
      });
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

  group('mergeIntoPreview (corrección por voz)', () {
    final catalog = [
      p('Águila Light', uuid: 'aguila'),
      p('Agua Cristal', uuid: 'agua'),
    ];
    PreviewModel base() => buildPreview(
          VoiceOrderResult.fromJson({
            'commands': [
              {'action': 'agregar', 'item': 'aguila', 'quantity': 2, 'raw': ''},
              {'action': 'agregar', 'item': 'agua', 'quantity': 1, 'raw': ''},
            ],
          }),
          catalog,
          resolver,
        );

    test('"agregue una agua más" acumula sobre la línea existente', () {
      final merged = mergeIntoPreview(
        base(),
        VoiceOrderResult.fromJson({
          'commands': [
            {'action': 'agregar', 'item': 'agua', 'quantity': 1, 'raw': 'una agua mas'}
          ]
        }),
        catalog,
        resolver,
      );
      final agua = merged.lines.firstWhere((l) => l.product!.uuid == 'agua');
      expect(agua.quantity, 2); // 1 + 1, no se duplica la línea
      expect(merged.lines.length, 2);
    });

    test('"quite la gaseosa/aguila" elimina la línea', () {
      final merged = mergeIntoPreview(
        base(),
        VoiceOrderResult.fromJson({
          'commands': [
            {'action': 'quitar', 'item': 'aguila', 'quantity': null, 'raw': 'quite'}
          ]
        }),
        catalog,
        resolver,
      );
      expect(merged.lines.any((l) => l.product!.uuid == 'aguila'), isFalse);
      expect(merged.lines.length, 1);
    });

    test('"que el agua sean tres" fija la cantidad', () {
      final merged = mergeIntoPreview(
        base(),
        VoiceOrderResult.fromJson({
          'commands': [
            {'action': 'fijar_cantidad', 'item': 'agua', 'quantity': 3, 'raw': ''}
          ]
        }),
        catalog,
        resolver,
      );
      final agua = merged.lines.firstWhere((l) => l.product!.uuid == 'agua');
      expect(agua.quantity, 3);
    });

    test('corrección que agrega un producto nuevo añade línea', () {
      final merged = mergeIntoPreview(
        base(),
        VoiceOrderResult.fromJson({
          'commands': [
            {'action': 'agregar', 'item': 'agua cristal', 'quantity': 1, 'raw': ''},
            {'action': 'fijar_mesa', 'target': {'type': 'mesa', 'mesa': '5'}, 'raw': ''}
          ]
        }),
        catalog,
        resolver,
      );
      expect(merged.target!.mesa, '5'); // destino actualizado
    });
  });
}
