import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/app_notification.dart';
import 'package:vendia_pos/widgets/notification_center_sheet.dart';

void main() {
  group('AppNotification.kindFromType', () {
    test('maps online_order -> webOrder', () {
      expect(AppNotification.kindFromType('online_order'),
          NotificationKind.webOrder);
      expect(AppNotification.kindFromType('online_order_accepted'),
          NotificationKind.webOrder);
    });

    test('maps fiado_* / debt / payment -> fiado', () {
      expect(AppNotification.kindFromType('fiado_accepted'),
          NotificationKind.fiado);
      expect(AppNotification.kindFromType('fiado_cancelled'),
          NotificationKind.fiado);
      expect(AppNotification.kindFromType('debt'), NotificationKind.fiado);
      expect(AppNotification.kindFromType('payment'), NotificationKind.fiado);
    });

    test('unknown / null / info fall back to system', () {
      expect(AppNotification.kindFromType(null), NotificationKind.system);
      expect(AppNotification.kindFromType(''), NotificationKind.system);
      expect(AppNotification.kindFromType('info'), NotificationKind.system);
      expect(AppNotification.kindFromType('future_event_v2'),
          NotificationKind.system);
    });
  });

  group('AppNotification.fromApi', () {
    test('returns null when id and title are missing', () {
      expect(AppNotification.fromApi(<String, dynamic>{}), isNull);
    });

    test('extracts order_id from nested data map', () {
      final n = AppNotification.fromApi({
        'id': 'n1',
        'title': 'Nuevo pedido',
        'type': 'online_order',
        'is_read': false,
        'created_at': '2026-04-22T14:00:00Z',
        'data': {'order_id': 'order-42'},
      });
      expect(n, isNotNull);
      expect(n!.kind, NotificationKind.webOrder);
      expect(n.orderId, 'order-42');
      expect(n.isRead, isFalse);
    });

    test('is defensive against malformed data field', () {
      final n = AppNotification.fromApi({
        'id': 'n2',
        'title': 't',
        'data': 'not-a-map',
      });
      expect(n, isNotNull);
      expect(n!.orderId, isNull);
      expect(n.fiadoId, isNull);
    });
  });

  group('bucketFor', () {
    final now = DateTime(2026, 4, 22, 10, 0);

    test('today when same calendar day', () {
      expect(bucketFor(DateTime(2026, 4, 22, 0, 5), now: now),
          NotificationDateBucket.today);
      expect(bucketFor(DateTime(2026, 4, 22, 23, 59), now: now),
          NotificationDateBucket.today);
    });

    test('yesterday when exactly one calendar day ago', () {
      expect(bucketFor(DateTime(2026, 4, 21, 23, 59), now: now),
          NotificationDateBucket.yesterday);
    });

    test('older for > 1 day and for null', () {
      expect(bucketFor(DateTime(2026, 4, 20, 12, 0), now: now),
          NotificationDateBucket.older);
      expect(bucketFor(null, now: now), NotificationDateBucket.older);
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 4, 22, 12, 0);

    test('under 1 minute -> "hace segundos"', () {
      expect(
          relativeTime(DateTime(2026, 4, 22, 11, 59, 30), now: now),
          'hace segundos');
    });

    test('minutes / hours / days / weeks', () {
      expect(relativeTime(DateTime(2026, 4, 22, 11, 45), now: now),
          'hace 15 min');
      expect(relativeTime(DateTime(2026, 4, 22, 9, 0), now: now),
          'hace 3 h');
      expect(relativeTime(DateTime(2026, 4, 20, 12, 0), now: now),
          'hace 2 d');
      expect(relativeTime(DateTime(2026, 4, 8, 12, 0), now: now),
          'hace 2 sem');
    });

    test('null timestamp returns empty string', () {
      expect(relativeTime(null, now: now), '');
    });
  });

  group('NotificationCenterSheet widget', () {
    Future<void> _pumpSheet(
      WidgetTester tester,
      List<AppNotification> items,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showNotificationCenter(ctx, items: items),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('renders empty state when list is empty', (tester) async {
      await _pumpSheet(tester, const []);
      expect(find.text('Sin actividad nueva'), findsOneWidget);
    });

    testWidgets('renders tiles grouped under Hoy when items are recent',
        (tester) async {
      final items = [
        AppNotification(
          id: '1',
          kind: NotificationKind.webOrder,
          title: 'Nuevo pedido en línea',
          body: 'Laura pidió por \$15.000',
          isRead: false,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          rawType: 'online_order',
        ),
        AppNotification(
          id: '2',
          kind: NotificationKind.fiado,
          title: 'Fiado aceptado',
          body: 'Carlos aceptó su fiado',
          isRead: true,
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          rawType: 'fiado_accepted',
        ),
      ];
      await _pumpSheet(tester, items);

      expect(find.text('Actividad reciente'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Nuevo pedido en línea'), findsOneWidget);
      expect(find.text('Fiado aceptado'), findsOneWidget);
      // Unread dot rendered for item #1 but not #2.
      expect(find.byKey(const Key('notification_unread_dot')), findsOneWidget);
    });

    testWidgets('splits into Hoy / Ayer / Más antiguas sections',
        (tester) async {
      final now = DateTime.now();
      final items = [
        AppNotification(
          id: 'today',
          kind: NotificationKind.webOrder,
          title: 'Hoy item',
          body: '',
          isRead: false,
          createdAt: now.subtract(const Duration(minutes: 10)),
          rawType: 'online_order',
        ),
        AppNotification(
          id: 'yesterday',
          kind: NotificationKind.fiado,
          title: 'Ayer item',
          body: '',
          isRead: true,
          createdAt: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(hours: 3)),
          rawType: 'fiado_accepted',
        ),
        AppNotification(
          id: 'old',
          kind: NotificationKind.system,
          title: 'Viejo item',
          body: '',
          isRead: true,
          createdAt: now.subtract(const Duration(days: 5)),
          rawType: 'info',
        ),
      ];
      await _pumpSheet(tester, items);

      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
      expect(find.text('Más antiguas'), findsOneWidget);
    });
  });
}
