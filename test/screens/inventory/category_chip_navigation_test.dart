// Spec: specs/102-completar-categorias-inventario/spec.md (FR-02, AC-01)
//
// El chip "Sin categoría (N)" aparece junto a los demás contadores de
// curaduría y al tocarlo NAVEGA a la vista dedicada CategoryCompletionScreen
// con la lista ya prefiltrada (solo productos sin categoría, sin borradores).
// Al volver, recarga el inventario para que el contador refleje el avance.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/category_completion_screen.dart';
import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/theme/app_theme.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._products) : super(AuthService());
  final List<Map<String, dynamic>> _products;
  int fetchCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchAllProducts(
      {String? branchId, bool sellableOnly = false}) async {
    fetchCalls++;
    return _products;
  }

  @override
  Future<List<Map<String, dynamic>>> suggestProductCategories() async => [];

  @override
  Future<List<String>> fetchProductCategories() async => [];
}

Map<String, dynamic> _p(
  String id,
  String name, {
  String category = '',
  bool draft = false,
}) =>
    {
      'id': id,
      'name': name,
      'barcode': '111',
      'price': 1000,
      'stock': 5,
      'category': category,
      'photo_url': '',
      'image_url': '',
      if (draft) 'is_draft': true,
    };

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  final products = [
    _p('1', 'Arroz Diana'),
    _p('2', 'Panela'),
    _p('3', 'Coca-Cola', category: 'Bebidas'),
    _p('4', 'Borrador fantasma', draft: true),
  ];

  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  testWidgets('el chip muestra el conteo sin borradores y con tap ≥44dp',
      (tester) async {
    final api = _FakeApi(products);
    await tester.pumpWidget(wrap(ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();

    // 2 sin categoría (el borrador y el categorizado quedan por fuera).
    expect(find.text('Sin categoría (2)'), findsOneWidget);
    final chip = find.ancestor(
        of: find.text('Sin categoría (2)'), matching: find.byType(ActionChip));
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
  });

  testWidgets('con todo categorizado el chip no aparece', (tester) async {
    final api = _FakeApi([_p('3', 'Coca-Cola', category: 'Bebidas')]);
    await tester.pumpWidget(wrap(ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Sin categoría'), findsNothing);
  });

  testWidgets('tocar el chip navega a CategoryCompletionScreen con la lista '
      'prefiltrada (FR-02)', (tester) async {
    final api = _FakeApi(products);
    await tester.pumpWidget(wrap(ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Sin categoría (2)'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryCompletionScreen), findsOneWidget);
    final screen = tester.widget<CategoryCompletionScreen>(
        find.byType(CategoryCompletionScreen));
    expect(screen.products.length, 2);
    expect(screen.products.map((p) => p['name']),
        containsAll(['Arroz Diana', 'Panela']));
  });

  testWidgets('al volver de la vista se recarga el inventario (FR-05)',
      (tester) async {
    final api = _FakeApi(products);
    await tester.pumpWidget(wrap(ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();
    final callsBefore = api.fetchCalls;

    await tester.tap(find.text('Sin categoría (2)'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(CategoryCompletionScreen))).pop();
    await tester.pumpAndSettle();

    expect(api.fetchCalls, greaterThan(callsBefore));
  });
}
