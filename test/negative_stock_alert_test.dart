import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/negative_stock_banner.dart';

void main() {
  group('isNegativeStock predicate', () {
    test('reservedStock greater than stock is negative', () {
      expect(isNegativeStock(2, 5), isTrue);
    });

    test('stock greater than reservedStock is not negative', () {
      expect(isNegativeStock(5, 2), isFalse);
    });

    test('stock equal to reservedStock is not negative (zero is fine)', () {
      expect(isNegativeStock(0, 0), isFalse);
      expect(isNegativeStock(3, 3), isFalse);
    });

    test('zero stock with non-zero reservation is negative', () {
      expect(isNegativeStock(0, 1), isTrue);
    });

    test('large negatives are still negative', () {
      expect(isNegativeStock(0, 999), isTrue);
      expect(isNegativeStock(-1, 0), isTrue);
    });
  });

  group('NegativeStockBanner widget', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders nothing when count is zero', (tester) async {
      await tester.pumpWidget(wrap(const NegativeStockBanner(count: 0)));
      await tester.pump();

      expect(find.byKey(const Key('negative_stock_banner_text')), findsNothing);
      // Sanity: a SizedBox.shrink should sit in the tree but no text.
      expect(find.textContaining('producto(s) con stock negativo'), findsNothing);
    });

    testWidgets('renders alert text when count is 3', (tester) async {
      await tester.pumpWidget(wrap(const NegativeStockBanner(count: 3)));
      await tester.pump();

      final textFinder = find.byKey(const Key('negative_stock_banner_text'));
      expect(textFinder, findsOneWidget);
      final widget = tester.widget<Text>(textFinder);
      expect(widget.data, contains('Tienes 3 producto(s)'));
      expect(widget.data, contains('Toca para regularizar'));
    });

    testWidgets('renders alert text when count is 1 (generic plural copy)',
        (tester) async {
      await tester.pumpWidget(wrap(const NegativeStockBanner(count: 1)));
      await tester.pump();

      final widget =
          tester.widget<Text>(find.byKey(const Key('negative_stock_banner_text')));
      expect(widget.data, contains('Tienes 1 producto(s)'));
    });

    testWidgets('reactive stream toggles visibility live', (tester) async {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(wrap(NegativeStockBanner(
        count: 0,
        countStream: controller.stream,
      )));
      await tester.pump();
      expect(find.byKey(const Key('negative_stock_banner_text')), findsNothing);

      controller.add(2);
      // Two pumps: one to drain the microtask that delivers the stream
      // event, one to rebuild the widget after StreamBuilder's setState.
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('negative_stock_banner_text')), findsOneWidget);
      expect(find.textContaining('Tienes 2 producto(s)'), findsOneWidget);

      controller.add(0);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('negative_stock_banner_text')), findsNothing);
    });

    testWidgets('onTap fires when banner is visible and pressed',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(NegativeStockBanner(
        count: 4,
        onTap: () => taps++,
      )));
      await tester.pump();

      await tester.tap(find.byKey(const Key('negative_stock_banner_tap')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });
}
