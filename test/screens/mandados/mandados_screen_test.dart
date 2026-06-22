// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/mandados/mandados_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  String? receivedId;
  @override
  Future<({int received, int skipped})> receiveErrand(String errandId) async {
    receivedId = errandId;
    return (received: 2, skipped: 0);
  }
  @override
  Future<List<Map<String, dynamic>>> fetchErrands({String status = ''}) async => [
        {
          'id': 'e1',
          'status': 'pendiente',
          'assignee_name': 'Yo mismo',
          'total_estimated': 12000,
          'lines': [
            {'name': 'Arroz', 'qty': 2, 'unit': 'kg'},
            {'name': 'Crema de leche', 'qty': 500, 'unit': 'ml'},
          ],
        },
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('el detalle del mandado lista los productos a comprar', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MandadosScreen(api: _FakeApi())));
    await tester.pumpAndSettle();

    // Ya no es solo "2 producto(s)": se ven los productos con su cantidad.
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Crema de leche'), findsOneWidget);
    expect(find.text('2 kg'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    // Y la acción para marcar comprado.
    expect(find.byKey(const Key('done_e1')), findsOneWidget);
  });

  testWidgets('"Ya compré" ingresa el inventario (llama a receiveErrand)', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: MandadosScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('done_e1')));
    await tester.pumpAndSettle();
    expect(api.receivedId, 'e1'); // ingresó el inventario, no solo cambió estado
    expect(find.textContaining('ingresado'), findsOneWidget);
  });
}
