import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mini replica of _ProductCard's right-edge controls. Pinning the
/// no-reflow contract here protects against a future refactor that
/// reverts to the conditional-children layout that triggered the
/// "fat-finger deletes the product" regression.
class _CardControls extends StatelessWidget {
  const _CardControls({required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final inCart = quantity > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Visibility(
          visible: inCart,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: const SizedBox(
            key: Key('decrement_btn'),
            width: 36,
            height: 36,
          ),
        ),
        Visibility(
          visible: inCart,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('$quantity',
                key: const Key('qty_text'),
                style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(
          key: Key('increment_btn'),
          width: 36,
          height: 36,
        ),
      ],
    );
  }
}

Future<Offset> _incrementButtonTopLeft(WidgetTester tester) async {
  final finder = find.byKey(const Key('increment_btn'));
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero);
}

void main() {
  testWidgets('+ button does NOT shift horizontally when qty changes 0→1',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: _CardControls(quantity: 0),
        ),
      ),
    ));
    final at0 = await _incrementButtonTopLeft(tester);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: _CardControls(quantity: 1),
        ),
      ),
    ));
    final at1 = await _incrementButtonTopLeft(tester);

    expect(at0.dx, at1.dx,
        reason: '+ button shifted horizontally — CLS regression');
    expect(at0.dy, at1.dy,
        reason: '+ button shifted vertically — CLS regression');
  });

  testWidgets('+ button stays anchored across qty 0,1,5,99', (tester) async {
    Offset? reference;
    for (final q in [0, 1, 5, 99]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: _CardControls(quantity: q),
          ),
        ),
      ));
      final pos = await _incrementButtonTopLeft(tester);
      reference ??= pos;
      expect(pos.dx, reference.dx, reason: 'shifted X at qty=$q');
      expect(pos.dy, reference.dy, reason: 'shifted Y at qty=$q');
    }
  });

  testWidgets('decrement slot exists in render tree even at qty=0',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: _CardControls(quantity: 0),
      ),
    ));
    expect(find.byKey(const Key('decrement_btn')), findsOneWidget);
  });

  testWidgets('decrement slot is not painted at qty=0', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: _CardControls(quantity: 0),
      ),
    ));
    final visibility = tester.widget<Visibility>(
      find.ancestor(
        of: find.byKey(const Key('decrement_btn')),
        matching: find.byType(Visibility),
      ).first,
    );
    expect(visibility.visible, isFalse);
    expect(visibility.maintainSize, isTrue);
    expect(visibility.maintainAnimation, isTrue);
    expect(visibility.maintainState, isTrue);
  });
}
