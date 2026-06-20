// Spec: specs/068-categorias-caracteristicas-producto/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/advanced_product_options.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController cat,
  required TextEditingController chars,
  List<String> suggestions = const [],
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AdvancedProductOptions(
          categoryController: cat,
          characteristicsController: chars,
          categorySuggestions: suggestions,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra los campos de categoría y características', (tester) async {
    await _pump(tester, cat: TextEditingController(), chars: TextEditingController());
    expect(find.byKey(const Key('product_category_field')), findsOneWidget);
    expect(find.byKey(const Key('product_characteristics_field')), findsOneWidget);
  });

  testWidgets('sugiere las categorías existentes y al tocar una la fija (antitypo)',
      (tester) async {
    final cat = TextEditingController();
    await _pump(tester,
        cat: cat,
        chars: TextEditingController(),
        suggestions: ['Gaseosas', 'Aseo', 'Granos']);

    // Aparecen como chips.
    expect(find.text('Gaseosas'), findsOneWidget);
    expect(find.text('Aseo'), findsOneWidget);

    // Tocar un chip pega el texto EXACTO en el controller.
    await tester.tap(find.byKey(const Key('category_suggestion_0')));
    await tester.pumpAndSettle();
    expect(cat.text, 'Gaseosas');
  });

  testWidgets('al escribir, filtra las sugerencias (case/acento-insensible)',
      (tester) async {
    final cat = TextEditingController();
    await _pump(tester,
        cat: cat,
        chars: TextEditingController(),
        suggestions: ['Gaseosas', 'Aseo', 'Granos']);

    await tester.enterText(find.byKey(const Key('product_category_field')), 'gas');
    await tester.pumpAndSettle();

    // 'Gaseosas' coincide; 'Aseo' no.
    expect(find.text('Gaseosas'), findsOneWidget);
    expect(find.text('Aseo'), findsNothing);
  });

  testWidgets('escribe características en su controller', (tester) async {
    final chars = TextEditingController();
    await _pump(tester, cat: TextEditingController(), chars: chars);
    await tester.enterText(
        find.byKey(const Key('product_characteristics_field')), 'Sin azúcar\nMarca Nacional');
    expect(chars.text, 'Sin azúcar\nMarca Nacional');
  });
}
