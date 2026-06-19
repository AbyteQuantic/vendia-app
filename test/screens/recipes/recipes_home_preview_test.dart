// Spec: specs/067-planear-menu-ia-ux/spec.md
//
// El hub "Mi menú" muestra un preview en vivo del catálogo en línea + el menú
// del día con los platos activos (resuelto igual que el link público).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/recipes/recipes_home_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  Map<String, dynamic> today = {
    'active': true,
    'found': true,
    'is_today': true,
    'day_label': '',
    'weekday': 'Lunes',
    'items': [
      {'recipe_uuid': 'r1', 'name': 'Bandeja paisa', 'planned_qty': 10},
      {'recipe_uuid': 'r2', 'name': 'Sancocho', 'planned_qty': 5},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchStoreConfig() async =>
      {'store_slug': 'mi-tienda'};

  @override
  Future<Map<String, dynamic>> fetchMenuToday({String branchId = ''}) async =>
      today;
}

Future<void> _pump(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(MaterialApp(home: RecipesHomeScreen(api: api)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('muestra el link en línea y los platos activos de hoy',
      (tester) async {
    await _pump(tester, _FakeApi());

    expect(find.text('Así se ve hoy su menú en línea'), findsOneWidget);
    expect(find.textContaining('mi-tienda'), findsOneWidget);
    expect(find.byKey(const Key('menu_preview_open')), findsOneWidget);
    // Los platos activos aparecen como chips.
    expect(find.text('Bandeja paisa'), findsOneWidget);
    expect(find.text('Sancocho'), findsOneWidget);
    expect(find.textContaining('2 platos'), findsOneWidget);
  });

  testWidgets('sin plan guardado invita a planear el menú', (tester) async {
    final api = _FakeApi()
      ..today = {'active': false, 'found': false, 'items': []};
    await _pump(tester, api);

    expect(find.textContaining('Aún no ha planeado su menú'), findsOneWidget);
  });

  testWidgets('plan activo pero hoy cerrado avisa que no hay menú',
      (tester) async {
    final api = _FakeApi()
      ..today = {'active': true, 'found': false, 'items': []};
    await _pump(tester, api);

    expect(find.textContaining('Hoy no hay menú publicado'), findsOneWidget);
  });

  testWidgets('conserva los accesos del hub (keys intactas)', (tester) async {
    await _pump(tester, _FakeApi());
    expect(find.byKey(const Key('recipes_option_list')), findsOneWidget);
    expect(find.byKey(const Key('recipes_option_plan')), findsOneWidget);
    // El acceso de voz queda al fondo del ListView perezoso: desplazarse a él.
    await tester.scrollUntilVisible(
      find.byKey(const Key('recipes_option_voice')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('recipes_option_voice')), findsOneWidget);
  });
}
