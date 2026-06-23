// Spec: specs/067-planear-menu-ia-ux/spec.md
//
// Cubre las ayudas inteligentes de "Planear menú": "Sugerir con IA" (fusión
// aditiva, whitelist, sin auto-guardar, deshabilitado sin recetas) y "Copiar a
// otros días" (replica + confirmación de reemplazo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/menu_planner_screen.dart';
import 'package:vendia_pos/theme/app_ui.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  List<Map<String, dynamic>> recipes = [
    {'id': 'r1', 'product_name': 'Bandeja paisa', 'category': 'Fuertes'},
    {'id': 'r2', 'product_name': 'Sancocho', 'category': 'Fuertes'},
    {'id': 'r3', 'product_name': 'Ajiaco', 'category': 'Fuertes'},
  ];
  Map<String, Map<String, dynamic>> plansByBranch = {'': {'days': {}}};
  Map<String, dynamic> suggestDays = {};
  int suggestCalls = 0;
  Map<String, dynamic>? savedDays;

  @override
  Future<List<Map<String, dynamic>>> fetchRecipes() async => recipes;

  @override
  Future<List<Map<String, dynamic>>> fetchIncompleteMenuItems() async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchBranches() async => [];

  @override
  Future<Map<String, dynamic>> fetchStoreConfig() async =>
      {'store_slug': 'mi-tienda'};

  @override
  Future<Map<String, dynamic>> fetchMenuPlan({String branchId = ''}) async =>
      plansByBranch[branchId] ?? {'days': {}};

  @override
  Future<List<Map<String, dynamic>>> fetchMenuOverrides(
          {String branchId = ''}) async =>
      [];

  @override
  Future<Map<String, dynamic>> suggestMenuPlan({String branchId = ''}) async {
    suggestCalls++;
    return {'days': suggestDays};
  }

  @override
  Future<Map<String, dynamic>> saveMenuPlan(Map<String, dynamic> days,
      {String branchId = ''}) async {
    savedDays = days;
    return {'days': days};
  }
}

Map<String, dynamic> _day(List<Map<String, dynamic>> items) =>
    {'enabled': true, 'items': items};
Map<String, dynamic> _item(String uuid, [int qty = 0]) =>
    {'recipe_uuid': uuid, 'planned_qty': qty};

Future<void> _pump(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(MaterialApp(home: MenuPlannerScreen(api: api)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('F2: cada día muestra un MinimalBadge de estado y se conservan keys',
      (tester) async {
    await _pump(tester, _FakeApi());
    // El badge del kit (no el borde de color crudo) marca el estado del día.
    expect(find.byType(MinimalBadge), findsWidgets);
    expect(find.text('Cerrado'), findsWidgets);
    expect(find.byKey(const Key('menu_planner_save')), findsOneWidget);
    expect(find.byKey(const Key('menu_day_switch_mon')), findsOneWidget);
  });

  testWidgets('F5: con menos de 3 recetas el botón Sugerir con IA está deshabilitado',
      (tester) async {
    final api = _FakeApi()
      ..recipes = [
        {'id': 'r1', 'product_name': 'Sopa'},
      ];
    await _pump(tester, api);

    expect(find.textContaining('al menos 3 recetas'), findsOneWidget);
    // Tocar el botón deshabilitado no dispara la sugerencia.
    await tester.tap(find.byKey(const Key('menu_suggest_ai')));
    await tester.pumpAndSettle();
    expect(api.suggestCalls, 0);
  });

  testWidgets('F4: Sugerir con IA fusiona aditivo, respeta whitelist y NO auto-guarda',
      (tester) async {
    final api = _FakeApi()
      // El martes ya está armado a mano (no se debe pisar).
      ..plansByBranch = {
        '': {
          'days': {'tue': _day([_item('r1', 3)])}
        }
      }
      // La IA propone: pisar martes (r2), llenar miércoles (r2 + uuid fantasma).
      ..suggestDays = {
        'tue': _day([_item('r2')]),
        'wed': _day([_item('r2'), _item('ghost')]),
      };
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('menu_suggest_ai')));
    await tester.pumpAndSettle();

    // No auto-guarda: el borrador vive en pantalla hasta el Guardar manual.
    expect(api.savedDays, isNull);

    // Al guardar: martes intacto (r1), miércoles con r2 (el fantasma se descarta).
    await tester.tap(find.byKey(const Key('menu_planner_save')));
    await tester.pumpAndSettle();

    final tue = api.savedDays!['tue'] as Map;
    expect((tue['items'] as List).length, 1);
    expect((tue['items'] as List).first['recipe_uuid'], 'r1');

    final wed = api.savedDays!['wed'] as Map;
    expect((wed['items'] as List).length, 1);
    expect((wed['items'] as List).first['recipe_uuid'], 'r2');
    expect(wed['enabled'], isTrue);
  });

  testWidgets('F3: Copiar a otros días replica los platos a un día vacío',
      (tester) async {
    final api = _FakeApi()
      ..plansByBranch = {
        '': {
          'days': {
            'mon': _day([_item('r1', 2), _item('r2', 1)])
          }
        }
      };
    await _pump(tester, api);

    // Abrir el editor del lunes (tiene 2 platos → ofrece "Copiar a otros días").
    await tester.ensureVisible(find.byKey(const Key('menu_day_mon')));
    await tester.tap(find.byKey(const Key('menu_day_mon')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_day_copy')));
    await tester.pumpAndSettle();

    // Elegir martes (vacío) y copiar.
    await tester.tap(find.byKey(const Key('menu_copy_target_tue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_copy_confirm')));
    await tester.pumpAndSettle();

    // Cerrar el editor y guardar.
    await tester.tap(find.byKey(const Key('menu_day_done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_planner_save')));
    await tester.pumpAndSettle();

    final tue = api.savedDays!['tue'] as Map;
    expect((tue['items'] as List).length, 2);
    expect((tue['items'] as List).map((e) => e['recipe_uuid']),
        containsAll(['r1', 'r2']));
  });

  testWidgets('F3: copiar sobre un día con platos pide confirmación',
      (tester) async {
    final api = _FakeApi()
      ..plansByBranch = {
        '': {
          'days': {
            'mon': _day([_item('r1', 2)]),
            'wed': _day([_item('r3', 1)]), // destino NO vacío
          }
        }
      };
    await _pump(tester, api);

    await tester.ensureVisible(find.byKey(const Key('menu_day_mon')));
    await tester.tap(find.byKey(const Key('menu_day_mon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_day_copy')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_copy_target_wed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_copy_confirm')));
    await tester.pumpAndSettle();

    // Como miércoles ya tenía platos, aparece la confirmación de reemplazo.
    expect(find.byKey(const Key('menu_copy_overwrite_confirm')), findsOneWidget);
  });
}
