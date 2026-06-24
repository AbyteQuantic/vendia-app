// Spec: specs/053 sync offline de mesas — lógica pura del PULL.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/open_tabs_merge.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 24, 10, 0, 0);
  final t1 = DateTime.utc(2026, 6, 24, 11, 0, 0); // más nuevo que t0

  group('planOpenTabsMerge — LWW por mesa', () {
    test('mesa que no existe local → create', () {
      final plan = planOpenTabsMerge(
        server: [OpenTabServerMeta(label: 'Mesa 1', updatedAt: t1)],
        localByLabel: const {},
      );
      expect(plan['Mesa 1'], OpenTabMergeAction.create);
    });

    test('local sin sincronizar → skip (no pisar cambios locales)', () {
      final plan = planOpenTabsMerge(
        server: [OpenTabServerMeta(label: 'Mesa 1', updatedAt: t1)],
        localByLabel: {
          'Mesa 1': OpenTabLocalMeta(updatedAt: t0, synced: false),
        },
      );
      expect(plan['Mesa 1'], OpenTabMergeAction.skip);
    });

    test('local synced y servidor más nuevo → replace', () {
      final plan = planOpenTabsMerge(
        server: [OpenTabServerMeta(label: 'Mesa 1', updatedAt: t1)],
        localByLabel: {
          'Mesa 1': OpenTabLocalMeta(updatedAt: t0, synced: true),
        },
      );
      expect(plan['Mesa 1'], OpenTabMergeAction.replace);
    });

    test('local synced y al día (o más nuevo) → skip', () {
      final plan = planOpenTabsMerge(
        server: [OpenTabServerMeta(label: 'Mesa 1', updatedAt: t0)],
        localByLabel: {
          'Mesa 1': OpenTabLocalMeta(updatedAt: t1, synced: true),
        },
      );
      expect(plan['Mesa 1'], OpenTabMergeAction.skip);
    });

    test('mezcla de varias mesas resuelve cada una por su cuenta', () {
      final plan = planOpenTabsMerge(
        server: [
          OpenTabServerMeta(label: 'A', updatedAt: t1), // nueva
          OpenTabServerMeta(label: 'B', updatedAt: t1), // synced viejo → replace
          OpenTabServerMeta(label: 'C', updatedAt: t1), // unsynced → skip
        ],
        localByLabel: {
          'B': OpenTabLocalMeta(updatedAt: t0, synced: true),
          'C': OpenTabLocalMeta(updatedAt: t0, synced: false),
        },
      );
      expect(plan['A'], OpenTabMergeAction.create);
      expect(plan['B'], OpenTabMergeAction.replace);
      expect(plan['C'], OpenTabMergeAction.skip);
    });
  });

  group('parseServerTimestamp', () {
    test('ISO válido', () {
      expect(parseServerTimestamp('2026-06-24T11:00:00Z'), t1);
    });
    test('DateTime se devuelve tal cual', () {
      expect(parseServerTimestamp(t1), t1);
    });
    test('vacío/garbage → null', () {
      expect(parseServerTimestamp(''), isNull);
      expect(parseServerTimestamp('no-es-fecha'), isNull);
      expect(parseServerTimestamp(null), isNull);
      expect(parseServerTimestamp(123), isNull);
    });
  });

  group('localTableTabFromServerJson', () {
    test('mapea label, ids, ítems y recomputa grossTotal', () {
      final tab = localTableTabFromServerJson({
        'order_id': 'ord-1',
        'session_token': 'sess-1',
        'label': 'Mesa 5',
        'status': 'preparando',
        'total': 999.0, // se IGNORA: grossTotal sale de los ítems
        'updated_at': '2026-06-24T11:00:00Z',
        'items': [
          {
            'product_uuid': 'p1',
            'product_name': 'Cerveza',
            'quantity': 2,
            'unit_price': 3500.0,
          },
          {
            'product_uuid': 'p2',
            'product_name': 'Empanada',
            'quantity': 3,
            'unit_price': 2000.0,
          },
        ],
      });

      expect(tab.label, 'Mesa 5');
      expect(tab.orderId, 'ord-1');
      expect(tab.sessionToken, 'sess-1');
      expect(tab.status, 'preparando');
      expect(tab.items, hasLength(2));
      expect(tab.items.first.productUuid, 'p1');
      expect(tab.items.first.quantity, 2);
      // 2*3500 + 3*2000 = 13000
      expect(tab.grossTotal, 13000.0);
      expect(tab.abonosTotal, 0.0);
      expect(tab.pendingBalance, 13000.0);
      expect(tab.updatedAt, t1);
      expect(tab.synced, isTrue);
    });

    test('sin ítems → grossTotal 0, defaults seguros', () {
      final tab = localTableTabFromServerJson({
        'label': 'Mesa 9',
        'items': <dynamic>[],
      });
      expect(tab.label, 'Mesa 9');
      expect(tab.items, isEmpty);
      expect(tab.grossTotal, 0.0);
      expect(tab.status, 'nuevo');
      expect(tab.synced, isTrue);
    });
  });
}
