// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/inventory/product_reorder_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>>? createdLines;
  @override
  Future<({List<Map<String, dynamic>> items, double total})> fetchProductReorderList() async => (
        items: [
          {'product_uuid': 'p1', 'line_kind': 'product', 'name': 'Gaseosa', 'unit': 'unidad',
           'shortfall': 9, 'stock': 1, 'min_stock': 10, 'unit_price': 2000, 'estimated_cost': 18000, 'is_estimate': false},
        ],
        total: 18000.0,
      );
  @override
  Future<Map<String, dynamic>> createErrand(
      {required List<Map<String, dynamic>> lines, String assigneeType = 'self', String assigneeId = '',
       String assigneeName = '', String assigneePhone = '', String title = '', String note = ''}) async {
    createdLines = lines;
    return {'errand': {'id': 'e1'}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('lista productos bajo mínimo y crea mandado de producto', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: ProductReorderScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Gaseosa'), findsOneWidget);
    expect(find.textContaining('Faltan 9'), findsOneWidget);
    // Crear mandado → líneas de PRODUCTO (line_kind=product).
    await tester.tap(find.byKey(const Key('create_reorder_errand')));
    await tester.pumpAndSettle();
    expect(api.createdLines, isNotNull);
    expect(api.createdLines!.first['line_kind'], 'product');
    expect(api.createdLines!.first['product_id'], 'p1');
  });
}
