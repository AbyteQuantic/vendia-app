// Spec: specs/065-recipe-studio/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/models/recipe.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/recipe_list_screen.dart';
import 'package:vendia_pos/screens/recipes/recipe_studio_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>> ingredients = [];
  final List<Map<String, dynamic>> created = [];
  final List<MapEntry<String, Map<String, dynamic>>> updated = [];

  List<Map<String, dynamic>> recipes = [];

  @override
  Future<List<Map<String, dynamic>>> fetchIngredients() async => ingredients;

  @override
  Future<List<Map<String, dynamic>>> fetchRecipes() async => recipes;

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

  final List<Map<String, dynamic>> createdIngredients = [];

  @override
  Future<Map<String, dynamic>> createIngredient(
      Map<String, dynamic> data) async {
    createdIngredients.add(data);
    return {
      'id': 'ing-${createdIngredients.length}',
      'name': data['name'],
      'unit': data['unit'],
      'unit_cost': data['unit_cost'],
      'stock': 0,
      'min_stock': 0,
    };
  }

  final List<MapEntry<String, Map<String, dynamic>>> updatedIngredients = [];

  @override
  Future<Map<String, dynamic>> updateIngredient(
      String uuid, Map<String, dynamic> data) async {
    updatedIngredients.add(MapEntry(uuid, data));
    return {...data, 'id': uuid};
  }

  String? describedName;
  @override
  Future<String> generateMenuDescription({required String name, String category = ''}) async {
    describedName = name;
    return 'Delicioso $name, recién hecho.';
  }

  @override
  Future<Map<String, dynamic>> fetchRecipeCost(String uuid) async =>
      {'total_cost': 0};

  Map<String, dynamic>? assistCurrent;
  Map<String, dynamic> assistResult = const {};

  @override
  Future<Map<String, dynamic>> recipeAssist({
    required String name,
    String instructions = '',
    Map<String, dynamic>? current,
  }) async {
    assistCurrent = current;
    return assistResult;
  }
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

  testWidgets('la ganancia usa las porciones (costo total ÷ rendimiento)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()..ingredients = [_ing('i1', 'Carne', cost: 1000)];
    await tester.pumpWidget(MaterialApp(home: RecipeStudioScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('studio_price')), '13000');
    // Agrega 1 insumo (costo total = 1000).
    await tester.ensureVisible(find.text('Agregar insumo'));
    await tester.tap(find.text('Agregar insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carne').last);
    await tester.pumpAndSettle();

    // Rinde 5 porciones → costo x plato = 1000/5 = 200; ganancia = 13000-200.
    await tester.enterText(find.widgetWithText(TextField, 'Porciones'), '5');
    await tester.pumpAndSettle();

    expect(find.text('Costo x plato'), findsOneWidget);
    expect(find.text('Ganancia x plato'), findsOneWidget);
    expect(find.text('\$200'), findsWidgets); // 1000 / 5
    expect(find.text('\$12.800'), findsWidgets); // 13.000 - 200
  });

  testWidgets('IA propone SOLO los pasos sin perder lo ya ingresado',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()
      ..ingredients = [_ing('i1', 'Carne', cost: 1000)]
      ..assistResult = {
        // La IA devuelve de todo, pero SOLO los pasos deben aplicarse.
        'name': 'NO DEBE PISAR EL NOMBRE',
        'yield': '99',
        'ingredients': [
          {'name': 'Cebolla', 'quantity': 2}
        ],
        'steps': ['Picar la carne', 'Sofreír', 'Servir'],
      };
    await tester.pumpWidget(MaterialApp(home: RecipeStudioScreen(api: api)));
    await tester.pumpAndSettle();

    // El tendero ya ingresó nombre, precio, un insumo y porciones.
    await tester.enterText(find.byKey(const Key('studio_name')), 'Lomo');
    await tester.enterText(find.byKey(const Key('studio_price')), '13000');
    await tester.ensureVisible(find.text('Agregar insumo'));
    await tester.tap(find.text('Agregar insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carne').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Porciones'), '5');
    await tester.pumpAndSettle();

    // Pide a la IA que proponga los pasos.
    await tester.ensureVisible(find.byKey(const Key('ia_steps')));
    await tester.tap(find.byKey(const Key('ia_steps')));
    await tester.pumpAndSettle();

    // Llegaron los pasos…
    expect(find.text('Picar la carne'), findsOneWidget);
    expect(find.text('Servir'), findsOneWidget);
    // …y mandó el contexto actual al backend.
    expect(api.assistCurrent?['name'], 'Lomo');
    // …sin pisar nombre ni inyectar ingredientes de la IA.
    expect(find.text('NO DEBE PISAR EL NOMBRE'), findsNothing);
    expect(find.text('Cebolla'), findsNothing);
    // …y el costeo por porción sigue intacto (1000 / 5 = 200).
    expect(find.text('\$200'), findsWidgets);
  });

  testWidgets('al crear, aterriza en el listado de recetas (no en la raíz)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1000)];

    // Pila: raíz ("RAIZ", simula el Dashboard) → push del Studio.
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RecipeStudioScreen(api: api))),
              child: const Text('RAIZ'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('RAIZ'));
    await tester.pumpAndSettle();

    // Mínimo para guardar: nombre, precio y un insumo.
    await tester.enterText(
        find.byKey(const Key('studio_name')), 'Arroz con pollo');
    await tester.enterText(find.byKey(const Key('studio_price')), '12000');
    await tester.ensureVisible(find.text('Agregar insumo'));
    await tester.tap(find.text('Agregar insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arroz').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Guardar plato'));
    await tester.tap(find.text('Guardar plato'));
    await tester.pumpAndSettle();

    expect(api.created, hasLength(1)); // sí creó
    expect(find.byType(RecipeStudioScreen), findsNothing); // salió del Studio
    expect(find.byType(RecipeListScreen), findsOneWidget); // aterrizó en el listado
    expect(find.text('RAIZ'), findsNothing); // NO volvió a la raíz/Dashboard
  });

  testWidgets('crear insumo inline (no bloqueante) lo agrega al plato',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Sin insumos registrados → debe ofrecer crearlos sin salir.
    final api = _FakeApi()..ingredients = [];
    await tester.pumpWidget(MaterialApp(home: RecipeStudioScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Crear insumo'));
    await tester.tap(find.text('Crear insumo'));
    await tester.pumpAndSettle();

    // Se abre la hoja rápida (no navega afuera).
    expect(find.text('Nuevo insumo'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del insumo'), 'Cebolla');
    await tester.enterText(
        find.widgetWithText(TextField, 'Costo por unidades'), '500');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear y agregar al plato'));
    await tester.pumpAndSettle();

    expect(api.createdIngredients.length, 1);
    expect(api.createdIngredients.first['name'], 'Cebolla');
    // Queda agregado como línea del plato.
    expect(find.text('Cebolla'), findsWidgets);
  });

  testWidgets('corregir el costo unitario de un insumo lo persiste y recalcula',
      (tester) async {
    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1000)];
    final recipe = Recipe(
      uuid: 'rec-9',
      productName: 'Arroz',
      salePrice: 9000,
      ingredients: [
        RecipeIngredient(
            ingredientUuid: 'i1', productName: 'Arroz', quantity: 3, unitCost: 1000),
      ],
    );
    await tester.pumpWidget(
        MaterialApp(home: RecipeStudioScreen(api: api, editing: recipe)));
    await tester.pumpAndSettle();

    // Costo precargado: 3 x 1.000 = 3.000.
    expect(find.text('\$3.000'), findsWidgets);

    // Tocar el costo del insumo y corregirlo a 2.000.
    await tester.ensureVisible(find.byKey(const Key('edit_cost_i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_cost_i1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unit_cost_field')), '2000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    // Persistió en el insumo y recalculó (3 x 2.000 = 6.000).
    expect(api.updatedIngredients.any((e) => e.key == 'i1' && e.value['unit_cost'] == 2000.0), isTrue);
    expect(find.text('\$6.000'), findsWidgets);
  });

  testWidgets('Generar descripción con IA precarga el campo', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1000)];
    await tester.pumpWidget(MaterialApp(home: RecipeStudioScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('studio_name')), 'Sancocho');
    await tester.ensureVisible(find.byKey(const Key('studio_describe_ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('studio_describe_ai')));
    await tester.pumpAndSettle();

    expect(api.describedName, 'Sancocho');
    expect(find.text('Delicioso Sancocho, recién hecho.'), findsOneWidget);
  });
}
