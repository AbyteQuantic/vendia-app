// Spec: specs/066-planear-menu/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/menu_planner_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  List<Map<String, dynamic>> recipes = [
    {'id': 'r1', 'product_name': 'Bandeja paisa', 'category': 'Fuertes'},
    {'id': 'r2', 'product_name': 'Sancocho', 'category': 'Fuertes'},
  ];
  // Por sede: plan por branchId ('' = comercio).
  Map<String, Map<String, dynamic>> plansByBranch = {'': {'days': {}}};
  List<Map<String, dynamic>> branches = [];
  Map<String, dynamic> storeConfig = {'store_slug': 'mi-tienda'};
  List<Map<String, dynamic>> overrides = [];
  Map<String, dynamic>? savedDays;
  String? savedBranchId;

  @override
  Future<List<Map<String, dynamic>>> fetchRecipes() async => recipes;

  @override
  Future<List<Map<String, dynamic>>> fetchBranches() async => branches;

  @override
  Future<Map<String, dynamic>> fetchStoreConfig() async => storeConfig;

  @override
  Future<Map<String, dynamic>> fetchMenuPlan({String branchId = ''}) async =>
      plansByBranch[branchId] ?? {'days': {}};

  @override
  Future<List<Map<String, dynamic>>> fetchMenuOverrides(
          {String branchId = ''}) async =>
      overrides;

  @override
  Future<Map<String, dynamic>> saveMenuPlan(Map<String, dynamic> days,
      {String branchId = ''}) async {
    savedDays = days;
    savedBranchId = branchId;
    return {'days': days};
  }
}

Future<void> _pump(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(MaterialApp(home: MenuPlannerScreen(api: api)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('muestra los 7 días con switches', (tester) async {
    await _pump(tester, _FakeApi());

    expect(find.text('Lunes'), findsOneWidget);
    expect(find.byKey(const Key('menu_day_switch_mon')), findsOneWidget);

    // Domingo va al fondo del ListView perezoso: hay que desplazarse.
    await tester.scrollUntilVisible(
      find.byKey(const Key('menu_day_switch_sun')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Domingo'), findsOneWidget);
    expect(find.byKey(const Key('menu_day_switch_sun')), findsOneWidget);
  });

  testWidgets('prende un día y lo persiste al guardar', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('menu_day_switch_thu')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('menu_planner_save')));
    await tester.pumpAndSettle();

    expect(api.savedDays, isNotNull);
    expect((api.savedDays!['thu'] as Map)['enabled'], isTrue);
    expect((api.savedDays!['mon'] as Map)['enabled'], isFalse);
  });

  testWidgets('precarga la plantilla existente del backend', (tester) async {
    final api = _FakeApi()
      ..plansByBranch = {
        '': {
          'days': {
            'fri': {
              'enabled': true,
              'items': [
                {'recipe_uuid': 'r1', 'planned_qty': 8}
              ]
            }
          }
        }
      };
    await _pump(tester, api);

    // El viernes muestra el conteo de recetas y la guía de preparación.
    expect(find.textContaining('1 receta'), findsOneWidget);
    expect(find.textContaining('8 por preparar'), findsOneWidget);
  });

  testWidgets('agregar una receta a un día desde el selector', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('menu_day_thu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_day_add_recipe')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipe_picker_search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recipe_pick_0')));
    await tester.pumpAndSettle();

    // La receta elegida aparece en el editor del día.
    expect(find.text('Bandeja paisa'), findsOneWidget);

    // Confirmar y guardar → el día queda con 1 ítem.
    await tester.tap(find.byKey(const Key('menu_day_done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_planner_save')));
    await tester.pumpAndSettle();

    final thu = api.savedDays!['thu'] as Map;
    expect((thu['items'] as List).length, 1);
    expect((thu['items'] as List).first['recipe_uuid'], 'r1');
  });

  group('por sede (Spec 066)', () {
    testWidgets('sin selector cuando hay 0 o 1 sede', (tester) async {
      final api = _FakeApi()..branches = [];
      await _pump(tester, api);
      expect(find.byKey(const Key('menu_branch_selector')), findsNothing);
    });

    testWidgets('con >1 sede muestra selector y guarda en la sede elegida',
        (tester) async {
      final api = _FakeApi()
        ..branches = [
          {'id': 'b1', 'name': 'Sede Norte', 'address': 'Cra 1'},
          {'id': 'b2', 'name': 'Sede Sur', 'address': 'Cra 9'},
        ]
        ..plansByBranch = {
          '': {'days': {}},
          'b1': {'days': {}},
        };
      await _pump(tester, api);

      expect(find.byKey(const Key('menu_branch_selector')), findsOneWidget);

      // Elegir la sede Norte (b1).
      await tester.tap(find.byKey(const Key('menu_branch_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Norte').last);
      await tester.pumpAndSettle();

      // El link por sede aparece.
      expect(find.byKey(const Key('menu_branch_link_copy')), findsOneWidget);

      // Prender un día y guardar → se guarda con branchId = b1. El switch del
      // jueves puede quedar bajo el fold (tarjeta de IA + selector de sede); la
      // lista agrupada construye las 7 filas de una, así que se usa
      // ensureVisible (scrollUntilVisible no desplaza si ya está en el árbol).
      await tester.ensureVisible(find.byKey(const Key('menu_day_switch_thu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_day_switch_thu')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('menu_planner_save')));
      await tester.pumpAndSettle();

      expect(api.savedBranchId, 'b1');
      expect((api.savedDays!['thu'] as Map)['enabled'], isTrue);
    });
  });
}
