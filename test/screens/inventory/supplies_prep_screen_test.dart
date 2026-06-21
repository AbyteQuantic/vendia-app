// Spec: specs/076-alistar-insumos-del-dia/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/inventory/supplies_prep_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  @override
  Future<Map<String, dynamic>> fetchSuppliesPrepList({required String date}) async => {
        'date': date,
        'weekday': 'Martes',
        'dishes': [
          {
            'recipe_uuid': 'r1', 'name': 'Bandeja', 'default_portions': 20,
            'ingredients': [
              {'ingredient_id': 'arroz', 'name': 'Arroz', 'unit': 'kg', 'qty_per_portion': 0.2},
              {'ingredient_id': 'papa', 'name': 'Papa', 'unit': 'kg', 'qty_per_portion': 0.5},
            ],
          },
        ],
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('totales por insumo = porciones × qty_per_portion (en vivo)', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SuppliesPrepScreen(api: _FakeApi())));
    await tester.pumpAndSettle();

    // 20 porciones: Arroz 0.2×20 = 4 kg, Papa 0.5×20 = 10 kg.
    expect(find.text('Bandeja'), findsOneWidget);
    expect(find.text('4 kg'), findsOneWidget);
    expect(find.text('10 kg'), findsOneWidget);

    // Sube una porción → 21: Arroz 4.2, Papa 10.5.
    await tester.tap(find.byKey(const Key('p_plus_r1')));
    await tester.pump();
    expect(find.text('4.20 kg'), findsOneWidget);
    expect(find.text('10.50 kg'), findsOneWidget);
  });
}
