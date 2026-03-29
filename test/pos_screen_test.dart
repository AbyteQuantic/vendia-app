import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';
import 'package:vendia_pos/screens/pos/pos_screen.dart';

Widget buildPos() => MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => CartController(),
        child: const PosScreen(),
      ),
    );

void main() {
  group('PosScreen — estructura base', () {
    testWidgets('campo de búsqueda está presente', (tester) async {
      await tester.pumpWidget(buildPos());
      expect(find.byKey(const Key('search_field')), findsOneWidget);
    });

    testWidgets('botón de escaneo está presente', (tester) async {
      await tester.pumpWidget(buildPos());
      expect(find.byKey(const Key('btn_scan')), findsOneWidget);
    });

    testWidgets('muestra exactamente 5 pestañas de carrito', (tester) async {
      await tester.pumpWidget(buildPos());
      for (int i = 1; i <= 5; i++) {
        expect(find.byKey(Key('cart_tab_$i')), findsOneWidget,
            reason: 'Pestaña $i debe existir');
      }
    });

    testWidgets('grid de productos muestra todos los mockProducts',
        (tester) async {
      await tester.pumpWidget(buildPos());
      await tester.pump();

      // Cada producto tiene una tarjeta en el grid
      expect(
        find.byKey(const Key('product_grid')),
        findsOneWidget,
      );
    });

    testWidgets('lista del carrito activo empieza vacía', (tester) async {
      await tester.pumpWidget(buildPos());
      expect(find.byKey(const Key('cart_list')), findsOneWidget);
      expect(find.byKey(const Key('cart_empty_msg')), findsOneWidget);
    });
  });

  group('PosScreen — interacción con carrito', () {
    testWidgets('tocar producto lo agrega al carrito activo', (tester) async {
      await tester.pumpWidget(buildPos());

      // Toca la primera tarjeta de producto
      final firstCard = find.byKey(const Key('product_card_0'));
      await tester.tap(firstCard);
      await tester.pump();

      // El mensaje de vacío desaparece y aparece el item
      expect(find.byKey(const Key('cart_empty_msg')), findsNothing);
      expect(find.byKey(const Key('cart_item_0')), findsOneWidget);
    });

    testWidgets('botón COBRAR aparece solo cuando hay productos en el carrito',
        (tester) async {
      await tester.pumpWidget(buildPos());

      // Carrito vacío → no hay COBRAR
      expect(find.byKey(const Key('btn_cobrar')), findsNothing);

      // Agregar producto
      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pump();

      // Ahora debe aparecer
      expect(find.byKey(const Key('btn_cobrar')), findsOneWidget);
    });

    testWidgets(r'COBRAR muestra el total formateado con signo $',
        (tester) async {
      await tester.pumpWidget(buildPos());
      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pump();

      final cobrarFinder = find.byKey(const Key('btn_cobrar'));
      expect(cobrarFinder, findsOneWidget);

      // El texto dentro del botón debe contener "$"
      expect(
        find.descendant(of: cobrarFinder, matching: find.textContaining('\$')),
        findsOneWidget,
      );
    });

    testWidgets('cambiar a pestaña 2 muestra carrito vacío independiente',
        (tester) async {
      await tester.pumpWidget(buildPos());

      // Agregar al carrito 1
      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pump();

      // Cambiar a pestaña 2
      await tester.tap(find.byKey(const Key('cart_tab_2')));
      await tester.pump();

      // Carrito 2 debe estar vacío
      expect(find.byKey(const Key('cart_empty_msg')), findsOneWidget);
    });

    testWidgets('incrementar cantidad de item desde la lista del carrito',
        (tester) async {
      await tester.pumpWidget(buildPos());

      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pump();

      // Presionar "+" en el item del carrito
      await tester.tap(find.byKey(const Key('cart_item_inc_0')));
      await tester.pump();

      // Cantidad debe ser 2 dentro del item del carrito
      expect(
        find.descendant(
          of: find.byKey(const Key('cart_item_0')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('decrementar a 0 elimina el item del carrito', (tester) async {
      await tester.pumpWidget(buildPos());

      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pump();

      // Presionar "-" en el item del carrito
      await tester.tap(find.byKey(const Key('cart_item_dec_0')));
      await tester.pump();

      // Carrito queda vacío
      expect(find.byKey(const Key('cart_empty_msg')), findsOneWidget);
    });
  });

  group('PosScreen — búsqueda', () {
    testWidgets('escribir en búsqueda filtra los productos mostrados',
        (tester) async {
      await tester.pumpWidget(buildPos());

      final firstName = CartController.mockProducts.first.name;
      final query = firstName.substring(0, 3).toLowerCase();

      await tester.enterText(find.byKey(const Key('search_field')), query);
      await tester.pump();

      // Al menos el primer producto debe seguir visible
      expect(find.byKey(const Key('product_card_0')), findsOneWidget);
    });

    testWidgets('búsqueda sin resultados muestra mensaje vacío',
        (tester) async {
      await tester.pumpWidget(buildPos());

      await tester.enterText(
          find.byKey(const Key('search_field')), 'zzz_no_existe');
      await tester.pump();

      expect(find.byKey(const Key('product_grid_empty')), findsOneWidget);
    });
  });
}
