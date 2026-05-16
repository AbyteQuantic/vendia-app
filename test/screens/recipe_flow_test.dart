// Spec: specs/001-insumos-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/recipe_step1_screen.dart';
import 'package:vendia_pos/screens/recipes/recipe_step2_screen.dart';
import 'package:vendia_pos/screens/recipes/recipe_step3_screen.dart';

/// Fake ApiService que reemplaza los datos mock de las pantallas de
/// receta. Verifica que el wizard de recetas ya NO usa `_MockIngredient`
/// ni categorías hardcoded: cablea `fetchIngredients`, `createRecipe` y
/// `fetchRecipeCost` reales (T-24, plan §5).
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  List<Map<String, dynamic>> ingredients = [];
  final List<Map<String, dynamic>> createdRecipes = [];
  Map<String, dynamic> recipeCost = {
    'total_cost': 0,
    'profit': 0,
    'margin_percent': 0,
  };

  @override
  Future<List<Map<String, dynamic>>> fetchIngredients() async => ingredients;

  @override
  Future<Map<String, dynamic>> createRecipe(
      Map<String, dynamic> data) async {
    createdRecipes.add(data);
    return {...data, 'uuid': data['uuid'] ?? 'recipe-1', 'id': 1};
  }

  @override
  Future<Map<String, dynamic>> fetchRecipeCost(String uuid) async =>
      recipeCost;
}

Map<String, dynamic> _ing(String uuid, String name,
        {String unit = 'unidad', double cost = 500}) =>
    {
      'uuid': uuid,
      'name': name,
      'unit': unit,
      'stock': 100,
      'min_stock': 0,
      'unit_cost': cost,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('paso 2 carga los insumos reales desde la API, no mocks',
      (tester) async {
    final api = _FakeApi()
      ..ingredients = [
        _ing('i1', 'Pan de Perro', cost: 500),
        _ing('i2', 'Salchicha', cost: 1500),
      ];

    await tester.pumpWidget(MaterialApp(
      home: RecipeStep2Screen(
        productName: 'Perro Caliente',
        salePrice: 5000,
        emoji: '🌭',
        category: 'Comidas',
        api: api,
      ),
    ));
    await tester.pumpAndSettle();

    // El insumo de la API aparece en el selector; el mock viejo no.
    await tester.tap(find.byKey(const Key('btn_pick_ingredient')));
    await tester.pumpAndSettle();

    expect(find.text('Pan de Perro'), findsWidgets);
    expect(find.text('Salchicha'), findsWidgets);
  });

  testWidgets('paso 2 muestra el estado vacío cuando no hay insumos',
      (tester) async {
    final api = _FakeApi()..ingredients = [];

    await tester.pumpWidget(MaterialApp(
      home: RecipeStep2Screen(
        productName: 'Perro Caliente',
        salePrice: 5000,
        emoji: '🌭',
        category: 'Comidas',
        api: api,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No tiene insumos'), findsOneWidget);
  });

  testWidgets('paso 3 persiste la receta vía createRecipe (no snackbar mock)',
      (tester) async {
    final api = _FakeApi();

    await tester.pumpWidget(MaterialApp(
      home: RecipeStep3Screen(
        productName: 'Perro Caliente',
        salePrice: 5000,
        emoji: '🌭',
        category: 'Comidas',
        ingredients: const [
          {
            'uuid': 'i1',
            'name': 'Pan de Perro',
            'quantity': 1.0,
            'unitCost': 500.0,
            'unit': 'unidad',
          },
        ],
        api: api,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_save_recipe')));
    // Bounded pumps: el snackbar de éxito dura 3 s, así que
    // pumpAndSettle no convergería. Basta con dejar resolver los
    // futures de createRecipe + fetchRecipeCost.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.createdRecipes, hasLength(1));
    final payload = api.createdRecipes.first;
    expect(payload['product_name'], 'Perro Caliente');
    expect(payload['sale_price'], 5000);
    // El insumo viaja con ingredient_uuid + quantity (contrato receta).
    final ings = payload['ingredients'] as List;
    expect(ings, hasLength(1));
    expect(ings.first['ingredient_uuid'], 'i1');
    expect(ings.first['quantity'], 1.0);
  });

  testWidgets('paso 1 navega a paso 2 con el precio que escribe el usuario',
      (tester) async {
    final api = _FakeApi()..ingredients = [_ing('i1', 'Pan')];

    await tester.pumpWidget(MaterialApp(
      home: RecipeStep1Screen(api: api),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('field_recipe_name')), 'Arepa de Huevo');
    await tester.enterText(
        find.byKey(const Key('field_recipe_price')), '3000');

    await tester.tap(find.byKey(const Key('btn_recipe_to_step2')));
    await tester.pumpAndSettle();

    // Llegamos al paso 2 y conserva el nombre escrito.
    expect(find.text('Arepa de Huevo'), findsWidgets);
  });
}
