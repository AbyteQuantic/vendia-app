// Spec: specs/065-recipe-studio/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/models/recipe.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/recipe_studio_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>> ingredients = [];
  final List<Map<String, dynamic>> created = [];
  final List<MapEntry<String, Map<String, dynamic>>> updated = [];

  @override
  Future<List<Map<String, dynamic>>> fetchIngredients() async => ingredients;

  @override
  Future<Map<String, dynamic>> createRecipe(Map<String, dynamic> data) async {
    created.add(data);
    return {...data, 'id': 'recipe-1', 'product_id': 'prod-1'};
  }

  @override
  Future<Map<String, dynamic>> updateRecipe(
      String uuid, Map<String, dynamic> data) async {
    updated.add(MapEntry(uuid, data));
    return {...data, 'id': uuid, 'product_id': 'prod-1'};
  }

  @override
  Future<Map<String, dynamic>> fetchRecipeCost(String uuid) async =>
      {'total_cost': 0};
}

Map<String, dynamic> _ing(String id, String name,
        {String unit = 'unidad', double cost = 500}) =>
    {'id': id, 'name': name, 'unit': unit, 'stock': 100, 'min_stock': 0, 'unit_cost': cost};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('Studio renderiza y carga insumos sin overflow a 360dp',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1500)];
    await tester.pumpWidget(MaterialApp(home: RecipeStudioScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo plato'), findsOneWidget);
    expect(find.textContaining('Ingredientes'), findsWidgets);
    expect(tester.takeException(), isNull); // sin overflow a 360dp
  });

  testWidgets('agregar un insumo actualiza el costo en vivo', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()..ingredients = [_ing('i1', 'Salchicha', cost: 1500)];
    await tester.pumpWidget(MaterialApp(home: RecipeStudioScreen(api: api)));
    await tester.pumpAndSettle();

    // Costo arranca en $0.
    expect(find.text('\$0'), findsWidgets);

    // Abre el Spotlight y elige el insumo.
    await tester.ensureVisible(find.text('Agregar insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar insumo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight_search')), findsOneWidget);
    await tester.tap(find.text('Salchicha').last);
    await tester.pumpAndSettle();

    // El costo del plato refleja el insumo (1.500).
    expect(find.text('\$1.500'), findsWidgets);
  });

  testWidgets('prefill de IA matchea ingredientes y carga pasos',
      (tester) async {
    final api = _FakeApi()
      ..ingredients = [_ing('i1', 'Arroz', cost: 1000), _ing('i2', 'Pollo', cost: 8000)];
    await tester.pumpWidget(MaterialApp(
      home: RecipeStudioScreen(api: api, initial: const {
        'name': 'Arroz con pollo',
        'ingredients': [
          {'name': 'arroz', 'quantity': 2, 'unit': 'kg'},
          {'name': 'pollo', 'quantity': 1, 'unit': 'unidad'},
          {'name': 'azafrán', 'quantity': 1, 'unit': 'g'}, // no existe como insumo
        ],
        'steps': ['Sofría el pollo', 'Agregue el arroz'],
      }),
    ));
    await tester.pumpAndSettle();

    // Nombre precargado.
    expect(find.widgetWithText(TextField, 'Nombre del plato'), findsOneWidget);
    // Los 2 insumos que SÍ existen quedan costeados; el inexistente se omite.
    expect(find.text('Arroz'), findsWidgets);
    expect(find.text('Pollo'), findsWidgets);
    // Pasos precargados.
    expect(find.text('Sofría el pollo'), findsOneWidget);
  });

  testWidgets('modo EDICIÓN precarga la receta y guarda con updateRecipe',
      (tester) async {
    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1000)];
    final recipe = Recipe(
      uuid: 'rec-9',
      productName: 'Arroz Editado',
      salePrice: 9000,
      category: 'Almuerzos',
      recipeYield: '4 porciones',
      prepTime: '20 min',
      prepSteps: const [
        {'text': 'Paso uno', 'photo_url': ''}
      ],
      ingredients: [
        RecipeIngredient(
            ingredientUuid: 'i1',
            productName: 'Arroz',
            quantity: 3,
            unitCost: 1000),
      ],
    );

    await tester.pumpWidget(
        MaterialApp(home: RecipeStudioScreen(api: api, editing: recipe)));
    await tester.pumpAndSettle();

    expect(find.text('Editar plato'), findsOneWidget);
    expect(find.text('Paso uno'), findsOneWidget);
    // Costo precargado: 3 × 1.000 = 3.000.
    expect(find.text('\$3.000'), findsWidgets);

    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    // No usamos pumpAndSettle: en el test esta pantalla es el home, así que
    // popUntil no la quita y el spinner de _saving giraría para siempre.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.updated.length, 1);
    expect(api.updated.first.key, 'rec-9');
    expect(api.created, isEmpty); // edición NO crea
    expect(api.updated.first.value['ingredients'], isNotEmpty);
  });
}
