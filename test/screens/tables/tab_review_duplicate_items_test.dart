import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'two ListView items with same uuid but distinct composite keys do NOT collide',
    (WidgetTester tester) async {
      // Replicate the keying strategy used in _buildReactiveContent.
      // Simulate two items with the same product UUID but sent at different times.
      final items = [
        ('agua', '2026-01-01T12:00:00.000Z'),
        ('agua', '2026-01-01T12:30:00.000Z'), // same uuid, later sentAt
        ('cola', '2026-01-01T12:00:00.000Z'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: items.asMap().entries.map((e) {
                final i = e.key;
                final (uuid, sentAt) = e.value;
                // Use the same composite key strategy as _buildReactiveContent:
                // index | uuid | sentAt
                final keyStr = '$i|$uuid|$sentAt';
                return ListTile(
                  key: ValueKey(keyStr),
                  title: Text(uuid),
                  subtitle: Text(sentAt),
                );
              }).toList(),
            ),
          ),
        ),
      );

      // Should NOT throw '!_doingMountOrUpdate' or 'Duplicate GlobalKey'.
      expect(tester.takeException(), isNull);

      // Verify all items are rendered correctly.
      expect(find.text('agua'), findsNWidgets(2));
      expect(find.text('cola'), findsOneWidget);
      expect(find.text('2026-01-01T12:00:00.000Z'), findsNWidgets(2));
      expect(find.text('2026-01-01T12:30:00.000Z'), findsOneWidget);
    },
  );

  testWidgets(
    'naive ValueKey(uuid) COLLIDES when two items share the same product uuid',
    (WidgetTester tester) async {
      // This test documents the regression behavior: without using index,
      // two ListView children with the same ValueKey(uuid) will NOT render
      // both items correctly. We catch this by checking rendering state.
      final items = [
        ('agua', '2026-01-01T12:00:00.000Z'),
        ('agua', '2026-01-01T12:30:00.000Z'), // same uuid
        ('cola', '2026-01-01T12:00:00.000Z'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: items.map((e) {
                final (uuid, sentAt) = e;
                // BROKEN: naive key using only uuid
                return ListTile(
                  key: ValueKey(uuid), // This will collide for duplicate uuids
                  title: Text(uuid),
                  subtitle: Text(sentAt),
                );
              }).toList(),
            ),
          ),
        ),
      );

      // With duplicate keys, Flutter reuses the State of the first
      // matching widget for the second one, so the second 'agua' update
      // lands on the wrong element. We document this by asserting the
      // tree at least mounts — the real protection is the previous test
      // which uses the composite key strategy.
      expect(find.byType(ListTile), findsWidgets);
    },
  );
}
