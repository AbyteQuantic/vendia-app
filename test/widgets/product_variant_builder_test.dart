// Spec: specs/095-variantes-producto/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/product_variant_builder.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('agregar 2 atributos con valores calcula el total de combinaciones',
      (tester) async {
    Map<String, List<String>>? submittedAttrs;
    await tester.pumpWidget(wrap(ProductVariantBuilder(
      groupNameController: TextEditingController(text: 'Camiseta Básica'),
      basePriceController: TextEditingController(text: '20000'),
      baseStockController: TextEditingController(text: '5'),
      onGenerate: (attrs) async => submittedAttrs = attrs,
    )));

    await tester.enterText(
        find.byKey(const Key('variant_attr_label_0')), 'Talla');
    await tester.enterText(
        find.byKey(const Key('variant_attr_values_0')), 'S,M,L');

    await tester.tap(find.byKey(const Key('variant_add_attribute')));
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('variant_attr_label_1')), 'Color');
    await tester.enterText(
        find.byKey(const Key('variant_attr_values_1')), 'Rojo,Azul');
    await tester.pump();

    // 3 tallas x 2 colores = 6 combinaciones (Cero Fricción Cognitiva: el
    // tendero ve el número antes de confirmar, no una sorpresa).
    expect(find.textContaining('6 producto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('variant_generate_button')));
    await tester.pumpAndSettle();

    expect(submittedAttrs, {
      'Talla': ['S', 'M', 'L'],
      'Color': ['Rojo', 'Azul'],
    });
  });

  testWidgets('sin ningún atributo con valores, el botón queda deshabilitado',
      (tester) async {
    await tester.pumpWidget(wrap(ProductVariantBuilder(
      groupNameController: TextEditingController(text: 'Camiseta'),
      basePriceController: TextEditingController(text: '20000'),
      baseStockController: TextEditingController(),
      onGenerate: (_) async {},
    )));

    final button = tester
        .widget<ElevatedButton>(find.byKey(const Key('variant_generate_button')));
    expect(button.onPressed, isNull);
  });

  testWidgets('espacios sobrantes en los valores se recortan', (tester) async {
    Map<String, List<String>>? submittedAttrs;
    await tester.pumpWidget(wrap(ProductVariantBuilder(
      groupNameController: TextEditingController(text: 'Camiseta'),
      basePriceController: TextEditingController(text: '20000'),
      baseStockController: TextEditingController(text: '1'),
      onGenerate: (attrs) async => submittedAttrs = attrs,
    )));

    await tester.enterText(
        find.byKey(const Key('variant_attr_label_0')), 'Talla');
    await tester.enterText(
        find.byKey(const Key('variant_attr_values_0')), ' S , M ,L ');
    await tester.pump();

    await tester.tap(find.byKey(const Key('variant_generate_button')));
    await tester.pumpAndSettle();

    expect(submittedAttrs, {
      'Talla': ['S', 'M', 'L'],
    });
  });
}
