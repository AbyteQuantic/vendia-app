// Feedback fundador 2026-07-20: el inventario vacío debe ofrecer los
// accionables de carga, no ser un callejón sin salida.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/add_merchandise_screen.dart';
import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._products) : super(AuthService());
  final List<Map<String, dynamic>> _products;

  @override
  Future<List<Map<String, dynamic>>> fetchAllProducts(
      {String? branchId, bool sellableOnly = false}) async => _products;

  @override
  Future<List<Map<String, dynamic>>> suggestProductCategories() async => [];

  @override
  Future<List<String>> fetchProductCategories() async => [];
}

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> ps) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ManageInventoryScreen(apiOverride: _FakeApi(ps)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('inventario vacío ofrece agregar e importar', (tester) async {
    await pump(tester, const []);
    expect(find.text('Inventario vacío'), findsOneWidget);
    expect(find.byKey(const Key('inventory_empty_add')), findsOneWidget);
    expect(find.byKey(const Key('inventory_empty_import')), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory_empty_add')));
    await tester.pumpAndSettle();
    expect(find.byType(AddMerchandiseScreen), findsOneWidget);
  });

  testWidgets('búsqueda sin resultados NO muestra los CTA de carga',
      (tester) async {
    await pump(tester, [
      {
        'id': '1',
        'name': 'Arroz',
        'barcode': '1',
        'price': 1000,
        'stock': 5,
        'category': '',
        'photo_url': '',
        'image_url': '',
      }
    ]);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron productos'), findsOneWidget);
    expect(find.byKey(const Key('inventory_empty_add')), findsNothing);
  });
}
