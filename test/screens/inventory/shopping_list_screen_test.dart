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
    expect(find.text('Últ. compra'), findsOneWidget); // badge de origen
    expect(find.text('\$8.400'), findsWidgets); // costo + total con formato COP
    expect(find.byKey(const Key('btn_send_list')), findsOneWidget); // enviar por WhatsApp
    expect(find.byKey(const Key('btn_nearby_from_shopping')), findsOneWidget);
    // los needs se enviaron al backend
    expect(api.sentNeeds!.first['ingredient_id'], 'arroz');
  });
}
