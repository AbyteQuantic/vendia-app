// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/inventory/shopping_list_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>>? sentNeeds;
  @override
  Future<Map<String, dynamic>?> matchTodayErrand(List<String> ids) async => null;
  @override
  Future<List<Map<String, dynamic>>> fetchSupplyOptions(
          {required String ingredientId, required String name, required String unit, required double shortfall}) async =>
      [
        {'id': 'chain:exito', 'label': 'Arroz x 5kg', 'supplier': 'Éxito', 'source': 'scraped_chain',
         'packs': 1, 'cost': 12000, 'leftover': 2000, 'pack_unknown': false, 'recommended': true, 'is_estimate': true},
      ];
  @override
  Future<Map<String, dynamic>> fetchShoppingList(List<Map<String, dynamic>> needs) async {
    sentNeeds = needs;
    return {
      'items': [
        {'ingredient_id': 'arroz', 'name': 'Arroz', 'unit': 'kg', 'needed': 5,
         'stock': 2, 'shortfall': 3, 'price_per_unit': 2800, 'estimated_cost': 8400,
         'price_source': 'ultima_compra', 'is_estimate': true},
      ],
      'total_estimated': 8400,
      'has_estimate': true,
      'disclaimer': 'Los precios marcados Estimado son cálculos…',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('muestra el faltante con costo, badge Estimado y total', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(
        home: ShoppingListScreen(
            needs: const [
              {'ingredient_id': 'arroz', 'name': 'Arroz', 'unit': 'kg', 'qty': 5}
            ],
            api: api)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shopping_list')), findsOneWidget);
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.textContaining('Faltan 3 kg'), findsOneWidget);
    expect(find.textContaining('aproximado'), findsWidgets); // sin empaque → aproximado
    expect(find.text('Tu costo'), findsOneWidget); // badge de origen
    expect(find.text('\$8.400'), findsWidgets); // costo + total con formato COP
    expect(find.byKey(const Key('btn_send_list')), findsOneWidget); // enviar por WhatsApp
    expect(find.byKey(const Key('btn_nearby_from_shopping')), findsOneWidget);
    // los needs se enviaron al backend
    expect(api.sentNeeds!.first['ingredient_id'], 'arroz');
  });

  testWidgets('elegir proveedor: la fila y el total reflejan la opción', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(
        home: ShoppingListScreen(
            needs: const [{'ingredient_id': 'arroz', 'name': 'Arroz', 'unit': 'kg', 'qty': 5}],
            api: api)));
    await tester.pumpAndSettle();

    // Antes de elegir: total = sugerido $8.400.
    expect(find.text('\$8.400'), findsWidgets);

    await tester.tap(find.byKey(const Key('options_arroz')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('option_chain:exito')));
    await tester.pumpAndSettle();

    // La fila muestra el proveedor elegido y su costo; el total recalcula.
    expect(find.textContaining('Éxito'), findsWidgets);
    expect(find.text('\$12.000'), findsWidgets); // costo de la opción + total
    expect(find.text('\$8.400'), findsNothing); // ya no manda el sugerido
  });
}
