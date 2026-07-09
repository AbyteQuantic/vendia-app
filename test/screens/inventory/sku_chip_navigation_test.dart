// Spec: specs/100-completar-skus-inventario/spec.md (T-14, FR-01, FR-14, AC-01)
//
// El chip "Sin SKU (N)" deja de ser un FilterChip in-place: al tocarlo
// NAVEGA a la vista dedicada `SkuCompletionScreen` con la lista ya
// prefiltrada (solo referencias físicas sin código, sin platos/servicios).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/screens/inventory/sku_completion_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

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
}

Map<String, dynamic> _p(
  String id,
  String name, {
  String barcode = '',
  bool menuItem = false,
}) =>
    {
      'id': id,
      'name': name,
      'barcode': barcode,
      'price': 1000,
      'stock': 5,
      'photo_url': '',
      'image_url': '',
      if (menuItem) 'is_menu_item': true,
    };

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  final products = [
    _p('1', 'Arroz Diana', barcode: ''),
    _p('2', 'Panela', barcode: ''),
    _p('3', 'Frijoles (plato)', barcode: '', menuItem: true),
    _p('4', 'Coca-Cola', barcode: '7702004003508'),
  ];

  testWidgets('el chip muestra el conteo físico y NO es un FilterChip',
      (tester) async {
    final api = _FakeApi(products);
    await tester.pumpWidget(
        MaterialApp(home: ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();

    // 2 físicas sin código (el plato queda por fuera — AC-09).
    expect(find.text('Sin SKU (2)'), findsOneWidget);
    // FR-14: el filtro in-place desapareció; el chip solo navega.
    expect(find.byType(FilterChip), findsNothing);
    // Audiencia 50+: objetivo táctil del chip ≥ 44dp de alto. (Desde Spec
    // 102 hay más de un ActionChip de curaduría → se ancla al texto.)
    final skuChip = find.ancestor(
        of: find.text('Sin SKU (2)'), matching: find.byType(ActionChip));
    expect(tester.getSize(skuChip).height, greaterThanOrEqualTo(44));
  });

  testWidgets('tocar el chip navega a SkuCompletionScreen con la lista '
      'prefiltrada (AC-01)', (tester) async {
    final api = _FakeApi(products);
    await tester.pumpWidget(
        MaterialApp(home: ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Sin SKU (2)'));
    await tester.pumpAndSettle();

    expect(find.byType(SkuCompletionScreen), findsOneWidget);
    final screen =
        tester.widget<SkuCompletionScreen>(find.byType(SkuCompletionScreen));
    expect(screen.products.length, 2);
    expect(screen.products.map((p) => p['name']),
        containsAll(['Arroz Diana', 'Panela']));
  });

  testWidgets('al volver de la vista se recarga el inventario (FR-08)',
      (tester) async {
    final api = _FakeApi(products);
    await tester.pumpWidget(
        MaterialApp(home: ManageInventoryScreen(apiOverride: api)));
    await tester.pump();
    await tester.pump();
    final callsBefore = api.fetchCalls;

    await tester.tap(find.text('Sin SKU (2)'));
    await tester.pumpAndSettle();
    // Volver de la vista dedicada.
    Navigator.of(tester.element(find.byType(SkuCompletionScreen))).pop();
    await tester.pumpAndSettle();

    expect(api.fetchCalls, greaterThan(callsBefore));
  });
}
