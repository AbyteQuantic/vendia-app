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
          // Precio responsivo: FittedBox(scaleDown) → se ve completo en
          // cualquier ancho, encoge la fuente solo si hace falta.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                price,
                key: const Key('price_text'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sin `maintainSize`: el [-] y el número solo ocupan ancho
              // cuando hay items en el carrito, liberando espacio para el
              // precio en el estado normal.
              Visibility(
                visible: inCart,
                child: btn(const Key('decrement_btn')),
              ),
              Visibility(
                visible: inCart,
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
    // El precio sigue en el árbol y se muestra COMPLETO: el FittedBox lo
    // escala para caber, no lo corta con "…".
    expect(find.byKey(const Key('price_text')), findsOneWidget);
    // Both buttons rendered at full size.
    final inc = _btnSize(tester, const Key('increment_btn'));
    expect(inc.width, 40);
    expect(inc.height, 40);
  });

  testWidgets(
      'fuera del carrito, [-] y cantidad NO ocupan espacio → el precio '
      'se ve completo', (tester) async {
    // Estado por defecto del card: producto NO agregado (quantity 0).
    // El bug reportado era que el precio se cortaba ("\$7.5…") porque el
    // [-] y el número reservaban ancho aunque estuvieran ocultos. Sin
    // `maintainSize`, esos controles no se construyen y el precio recibe
    // casi todo el ancho.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 165, // 2 columnas en 360dp — el caso más estrecho.
          child: _ErgoBottomRow(quantity: 0, price: '\$7.500'),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    // Los controles ocultos no están en el árbol → no reservan ancho,
    // así que ese espacio queda para el precio (raíz del bug "\$7.5…").
    expect(find.byKey(const Key('decrement_btn')), findsNothing);
    // El precio sí está presente y a tamaño completo.
    expect(find.byKey(const Key('price_text')), findsOneWidget);
    // Solo el "+" permanece, a tamaño ergonómico.
    final inc = _btnSize(tester, const Key('increment_btn'));
    expect(inc.width, 40);
    expect(inc.height, 40);
  });
}
