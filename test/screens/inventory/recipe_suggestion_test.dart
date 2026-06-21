// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/inventory/create_product_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Finder> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
    await tester.pump();
    final f = find.widgetWithText(TextFormField, 'Buscar o escribir nombre...');
    expect(f, findsOneWidget);
    return f;
  }

  testWidgets('#10 nombre preparable (Empanada) sugiere crear receta', (tester) async {
    final name = await open(tester);
    await tester.enterText(name, 'Empanada de carne');
    await tester.pump();
    expect(find.byKey(const Key('suggest_recipe_cta')), findsOneWidget);
    expect(find.textContaining('como RECETA'), findsOneWidget);
  });

  testWidgets('#10 producto NO preparable (Coca Cola) no sugiere receta', (tester) async {
    final name = await open(tester);
    await tester.enterText(name, 'Coca Cola');
    await tester.pump();
    expect(find.byKey(const Key('suggest_recipe_cta')), findsNothing);
  });
}
