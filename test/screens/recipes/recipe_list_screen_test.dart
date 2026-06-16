// Spec: specs/043-menu-restaurante-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/recipes/recipe_list_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._recipes, {this.fail = false}) : super(AuthService());
  final List<Map<String, dynamic>> _recipes;
  final bool fail;
  final List<String> deleted = [];

  @override
  Future<List<Map<String, dynamic>>> fetchRecipes() async {
    if (fail) {
      throw const AppError(type: AppErrorType.network, message: 'sin conexión');
    }
    return _recipes;
  }

  @override
  Future<void> deleteRecipe(String uuid) async => deleted.add(uuid);
}

Map<String, dynamic> _recipe(String name, num price, List ingredients) => {
      'id': '11111111-1111-4111-8111-${name.hashCode.abs().toString().padLeft(12, '0').substring(0, 12)}',
      'product_name': name,
      'category': 'Platos',
      'sale_price': price,
      'ingredients': ingredients,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('lista recetas con precio, costo y ganancia', (tester) async {
    final api = _FakeApi([
      _recipe('Bandeja Paisa', 25000, [
        {'ingredient_uuid': 'a1', 'product_name': 'Frijol', 'quantity': 1, 'unit_cost': 3000},
        {'ingredient_uuid': 'a2', 'product_name': 'Arroz', 'quantity': 1, 'unit_cost': 1000},
      ]),
    ]);
    await tester.pumpWidget(MaterialApp(home: RecipeListScreen(apiOverride: api)));
    await tester.pump(); // resuelve el future
    await tester.pump();

    expect(find.text('Bandeja Paisa'), findsOneWidget);
    // costo = 4000, ganancia = 21000
    expect(find.textContaining('Ganancia'), findsOneWidget);
    expect(find.textContaining('2 insumos'), findsOneWidget);
  });

  testWidgets('estado vacío con CTA cuando no hay recetas', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: RecipeListScreen(apiOverride: _FakeApi([]))));
    await tester.pump();
    await tester.pump();
    expect(find.text('Aún no tiene recetas'), findsOneWidget);
    expect(find.text('Crear receta'), findsOneWidget);
  });

  testWidgets('estado de error con Reintentar', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RecipeListScreen(apiOverride: _FakeApi([], fail: true))));
    await tester.pump();
    await tester.pump();
    expect(find.text('sin conexión'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
