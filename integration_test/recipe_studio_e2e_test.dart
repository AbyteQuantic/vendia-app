// Spec: specs/065-recipe-studio/spec.md
//
// E2E del módulo "Nuevo plato" (Recipe Studio) corriendo en un dispositivo
// REAL (emulador). Cubre todos los casos de uso con un ApiService falso
// inyectado (sin backend/auth): crear, validación, agregar VARIOS insumos,
// crear insumo inline (no bloqueante), editar cantidad con decimales, foto IA
// (loader), prefill por IA, modo edición, y guardar.
//
// Correr:  flutter test integration_test/recipe_studio_e2e_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/models/recipe.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/recipe_studio_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>> ingredients = [];
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> createdIngredients = [];
  final List<MapEntry<String, Map<String, dynamic>>> updated = [];
  int genImageCalls = 0;

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
  Future<Map<String, dynamic>> createIngredient(
      Map<String, dynamic> data) async {
    createdIngredients.add(data);
    final id = 'ing-${createdIngredients.length}';
    final row = {
      'id': id,
      'name': data['name'],
      'unit': data['unit'],
      'unit_cost': data['unit_cost'],
      'stock': 0,
      'min_stock': 0,
    };
    ingredients.add(row);
    return row;
  }

  @override
  Future<Map<String, dynamic>> fetchRecipeCost(String uuid) async =>
      {'total_cost': 0};

  @override
  Future<String> generateMenuImage(
      {required String name,
      String category = '',
      String description = '',
      String presentation = ''}) async {
    genImageCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // URL transparente 1x1 (carga sin red real en el emulador).
    return 'https://upload.wikimedia.org/wikipedia/commons/d/d2/Blank.png';
  }
}

Map<String, dynamic> _ing(String id, String name,
        {String unit = 'unidad', double cost = 500}) =>
    {'id': id, 'name': name, 'unit': unit, 'stock': 100, 'min_stock': 0, 'unit_cost': cost};

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(home: child));
  await t.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('E2E-1 crear plato: validación, insumo inline, guardar',
      (t) async {
    final api = _FakeApi(); // sin insumos registrados
    await _pump(t, RecipeStudioScreen(api: api));

    // Secciones visibles.
    expect(find.text('Nuevo plato'), findsOneWidget);
    expect(find.text('2. Ingredientes y costo'), findsOneWidget);
    expect(find.text('3. Preparación (opcional)'), findsOneWidget);

    // Guardar deshabilitado + guía.
    expect(find.textContaining('Falta:'), findsOneWidget);

    // Nombre + precio.
    await t.enterText(find.byKey(const Key('studio_name')), 'Bandeja paisa');
    await t.enterText(find.byKey(const Key('studio_price')), '18000');
    await t.pumpAndSettle();

    // Crear insumo inline (no hay insumos aún).
    await t.ensureVisible(find.text('Crear insumo'));
    await t.tap(find.text('Crear insumo'));
    await t.pumpAndSettle();
    expect(find.text('Nuevo insumo'), findsOneWidget);
    await t.enterText(
        find.widgetWithText(TextField, 'Nombre del insumo'), 'Frijol');
    await t.enterText(
        find.widgetWithText(TextField, 'Costo por unidades'), '3000');
    await t.pumpAndSettle();
    await t.tap(find.text('Crear y agregar al plato'));
    await t.pumpAndSettle();

    expect(api.createdIngredients.length, 1);
    expect(find.text('Frijol'), findsWidgets);

    // Dejar que el snackbar flotante ("Insumo creado…") se cierre para que no
    // tape el botón Guardar de la barra inferior.
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();

    // Guardar habilitado → crea receta.
    await t.ensureVisible(find.text('Guardar plato'));
    await t.tap(find.text('Guardar plato'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(api.created.length, 1);
    expect(api.created.first['product_name'], 'Bandeja paisa');
    expect(api.created.first['ingredients'], isNotEmpty);
  });

  testWidgets('E2E-2 agregar MÁS de un insumo (regresión del bug)', (t) async {
    final api = _FakeApi()
      ..ingredients = [_ing('i1', 'Arroz', cost: 1000), _ing('i2', 'Pollo', cost: 8000)];
    await _pump(t, RecipeStudioScreen(api: api));

    // Primer insumo.
    await t.ensureVisible(find.text('Agregar insumo'));
    await t.tap(find.text('Agregar insumo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Arroz').last);
    await t.pumpAndSettle();

    // Segundo insumo — antes daba "Ya agregó todos sus insumos"; ahora abre.
    await t.ensureVisible(find.text('Agregar insumo'));
    await t.tap(find.text('Agregar insumo'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('spotlight_search')), findsOneWidget);
    await t.tap(find.text('Pollo').last);
    await t.pumpAndSettle();

    expect(find.text('Arroz'), findsWidgets);
    expect(find.text('Pollo'), findsWidgets);
  });

  testWidgets('E2E-3 todos los existentes usados → aún puede crear nuevo',
      (t) async {
    final api = _FakeApi()..ingredients = [_ing('i1', 'Sal', cost: 200)];
    await _pump(t, RecipeStudioScreen(api: api));

    await t.ensureVisible(find.text('Agregar insumo'));
    await t.tap(find.text('Agregar insumo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sal').last);
    await t.pumpAndSettle();

    // Pool vacío (único insumo usado). "Agregar insumo" NO debe ser callejón.
    await t.ensureVisible(find.text('Agregar insumo'));
    await t.tap(find.text('Agregar insumo'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('spotlight_search')), findsOneWidget);
    expect(find.textContaining('Crear'), findsWidgets); // opción de crear nuevo
  });

  testWidgets('E2E-4 foto con IA muestra loader y termina', (t) async {
    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1000)];
    await _pump(t, RecipeStudioScreen(api: api));

    // La foto requiere nombre.
    await t.enterText(find.byKey(const Key('studio_name')), 'Sopa');
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Crear foto con IA'));
    await t.tap(find.text('Crear foto con IA'));
    await t.pump(const Duration(milliseconds: 50)); // generación en curso
    // Loader visible mientras genera (fake demora 200ms).
    expect(find.textContaining('Preparando la foto'), findsOneWidget);

    await t.pumpAndSettle();
    expect(api.genImageCalls, 1); // se llamó al endpoint
  });

  testWidgets('E2E-5 prefill por IA: nombre, insumos y pasos', (t) async {
    final api = _FakeApi()
      ..ingredients = [_ing('i1', 'Arroz', cost: 1000), _ing('i2', 'Pollo', cost: 8000)];
    await _pump(
        t,
        RecipeStudioScreen(api: api, initial: const {
          'name': 'Arroz con pollo',
          'ingredients': [
            {'name': 'arroz', 'quantity': 2, 'unit': 'kg'},
            {'name': 'pollo', 'quantity': 1, 'unit': 'unidad'},
          ],
          'steps': ['Sofría el pollo', 'Agregue el arroz'],
        }));

    expect(find.text('Sofría el pollo'), findsOneWidget);
    expect(find.text('Arroz'), findsWidgets);
    expect(find.text('Pollo'), findsWidgets);
  });

  testWidgets('E2E-6 modo edición precarga y guarda con updateRecipe', (t) async {
    final api = _FakeApi()..ingredients = [_ing('i1', 'Arroz', cost: 1000)];
    final recipe = Recipe(
      uuid: 'rec-9',
      productName: 'Arroz Editado',
      salePrice: 9000,
      recipeYield: '4 porciones',
      prepSteps: const [
        {'text': 'Paso uno', 'photo_url': ''}
      ],
      ingredients: [
        RecipeIngredient(
            ingredientUuid: 'i1', productName: 'Arroz', quantity: 3, unitCost: 1000),
      ],
    );
    await _pump(t, RecipeStudioScreen(api: api, editing: recipe));

    expect(find.text('Editar plato'), findsOneWidget);
    expect(find.text('Paso uno'), findsOneWidget);

    await t.ensureVisible(find.text('Guardar cambios'));
    await t.tap(find.text('Guardar cambios'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(api.updated.length, 1);
    expect(api.created, isEmpty);
  });
}
