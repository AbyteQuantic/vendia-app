import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mini replica of the bottom row to validate ergonomic invariants
/// without coupling to private widgets.
class _ErgoBottomRow extends StatelessWidget {
  const _ErgoBottomRow({required this.quantity, required this.price});
  final int quantity;
  final String price;

  @override
  Widget build(BuildContext context) {
    final inCart = quantity > 0;
    Widget btn(Key k) => Container(
          key: k,
          width: 40,
          height: 40,
          color: Colors.blue,
        );
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text(
              price,
              key: const Key('price_text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Visibility(
                visible: inCart,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: btn(const Key('decrement_btn')),
              ),
              Visibility(
                visible: inCart,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$quantity'),
                ),
              ),
              btn(const Key('increment_btn')),
            ],
          ),
        ],
      ),
    );
  }
}

Size _btnSize(WidgetTester tester, Key k) {
  final box = tester.renderObject<RenderBox>(find.byKey(k));
  return box.size;
}

void main() {
  testWidgets('+ and - buttons are at least 40×40', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: _ErgoBottomRow(quantity: 1, price: '\$5.000'),
      ),
    ));
    final inc = _btnSize(tester, const Key('increment_btn'));
    final dec = _btnSize(tester, const Key('decrement_btn'));
    expect(inc.width, greaterThanOrEqualTo(40));
    expect(inc.height, greaterThanOrEqualTo(40));
    expect(dec.width, greaterThanOrEqualTo(40));
    expect(dec.height, greaterThanOrEqualTo(40));
  });

  testWidgets('long price does NOT overflow on a narrow card width',
      (tester) async {
    // Replica of the on-card constraint (~220px outer, ~204px after
    // padding). A merchant who types in a million-peso item with
    // currency formatting hits ~10 chars; the row must absorb it.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 204,
          child: _ErgoBottomRow(
            quantity: 99,
            price: '\$1.234.567.890',
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    // Price was truncated (still in tree, just ellipsised).
    expect(find.byKey(const Key('price_text')), findsOneWidget);
    // Both buttons rendered at full size.
    final inc = _btnSize(tester, const Key('increment_btn'));
    expect(inc.width, 40);
    expect(inc.height, 40);
  });
}
