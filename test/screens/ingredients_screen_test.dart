// Spec: specs/001-insumos-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/screens/inventory/ingredients_screen.dart';

/// Fake ApiService que permite controlar la respuesta de los endpoints
/// de insumos sin red. Cubre los 3 estados obligatorios de UI_RULES §8
/// (loading / empty / error) y el flujo CRUD.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  bool throwOnFetch = false;
  List<Map<String, dynamic>> ingredients = [];
  final List<Map<String, dynamic>> created = [];
  final List<String> deleted = [];

  @override
  Future<List<Map<String, dynamic>>> fetchIngredients() async {
    if (throwOnFetch) {
      throw const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión',
      );
    }
    return ingredients;
  }

  @override
  Future<Map<String, dynamic>> createIngredient(
      Map<String, dynamic> data) async {
    created.add(data);
    // El backend asigna `id` (UUID) y devuelve la entidad completa; el
    // cuerpo del POST no incluye el identificador (contrato Feature 001).
    final res = {
      ...data,
      'id': 'ing-created-${created.length}',
    };
    ingredients = [...ingredients, res];
    return res;
  }

  @override
  Future<Map<String, dynamic>> updateIngredient(
      String uuid, Map<String, dynamic> data) async {
    return {...data, 'id': uuid};
  }

  @override
  Future<void> deleteIngredient(String uuid) async {
    deleted.add(uuid);
    ingredients = ingredients.where((i) => i['id'] != uuid).toList();
  }
}

/// Construye un insumo con la forma REAL del backend: el identificador
/// viaja en la llave `id` (no `uuid`), porque el modelo Go embebe
/// `BaseModel`.
Map<String, dynamic> _ing({
  required String id,
  required String name,
  String unit = 'kg',
  double stock = 5,
  double minStock = 2,
  double unitCost = 1000,
}) =>
    {
      'id': id,
      'tenant_id': 'tenant-1',
      'name': name,
      'unit': unit,
      'stock': stock,
      'min_stock': minStock,
      'unit_cost': unitCost,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('muestra un indicador de carga mientras pide los insumos',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));

    // Primer frame: aún sin resolver el Future.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('estado vacío en español con CTA cuando no hay insumos',
      (tester) async {
    final api = _FakeApi()..ingredients = [];
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tiene insumos'), findsOneWidget);
    expect(find.text('Agregar insumo'), findsWidgets);
  });

  testWidgets('estado de error en español con botón Reintentar',
      (tester) async {
    final api = _FakeApi()..throwOnFetch = true;
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    // Nunca se filtra un stack trace (UI_RULES §8).
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('lista los insumos con su stock y unidad (AC-01)',
      (tester) async {
    final api = _FakeApi()
      ..ingredients = [
        _ing(id: 'i1', name: 'Arroz', unit: 'kg', stock: 10),
        _ing(id: 'i2', name: 'Pollo', unit: 'kg', stock: 3),
      ];
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Pollo'), findsOneWidget);
    // El stock con su unidad legible aparece en la tarjeta.
    expect(find.textContaining('10'), findsWidgets);
  });

  testWidgets(
      'lista insumos con la forma REAL del backend — id, no uuid (BUG-5)',
      (tester) async {
    // Regresión BUG-5: el backend serializa el identificador del insumo
    // como `id` (su modelo Go embebe BaseModel). Antes la pantalla leía
    // `uuid`, el cast `null as String` lanzaba TypeError y `catch (_)`
    // lo tragaba → la pantalla mostraba el estado de error con un 200.
    final api = _FakeApi()
      ..ingredients = [
        {
          'id': '2f8c0a1e-9b3d-4f6a-8c11-aa22bb33cc44',
          'tenant_id': 'tenant-1',
          'name': 'Harina',
          'unit': 'kg',
          'stock': 8.0,
          'min_stock': 1.0,
          'unit_cost': 2500.0,
          'created_at': '2026-05-16T10:00:00Z',
          'updated_at': '2026-05-16T10:00:00Z',
        },
      ];
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    // Lista los datos de verdad — no cae al estado de error.
    expect(find.text('Harina'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('marca el insumo bajo el mínimo (AC-05)', (tester) async {
    final api = _FakeApi()
      ..ingredients = [
        _ing(id: 'i1', name: 'Sal', unit: 'g', stock: 1, minStock: 2),
      ];
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Stock bajo'), findsOneWidget);
  });

  testWidgets('el header no tiene más de 2 acciones laterales (UI_RULES §1)',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect((appBar.actions ?? const []).length, lessThanOrEqualTo(2));
  });

  testWidgets('crear un insumo desde el formulario lo persiste vía la API',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    // Abre el formulario con la acción "Agregar insumo".
    await tester.tap(find.byKey(const Key('btn_add_ingredient')).first);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('field_ingredient_name')), 'Aceite');
    await tester.enterText(
        find.byKey(const Key('field_ingredient_stock')), '4');
    await tester.enterText(
        find.byKey(const Key('field_ingredient_cost')), '12000');

    await tester.tap(find.byKey(const Key('btn_save_ingredient')));
    await tester.pumpAndSettle();

    expect(api.created, hasLength(1));
    expect(api.created.first['name'], 'Aceite');
  });

  testWidgets('rechaza guardar un insumo sin nombre', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: IngredientsScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_add_ingredient')).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_save_ingredient')));
    await tester.pumpAndSettle();

    // Sin nombre no se llama a la API.
    expect(api.created, isEmpty);
    expect(find.text('Escriba el nombre del insumo'), findsOneWidget);
  });
}
