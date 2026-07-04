// Spec: specs/095-variantes-producto/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/create_variant_group_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  Map<String, dynamic>? createdGroupPayload;
  Map<String, dynamic>? generatedPayload;
  String? generatedGroupId;

  @override
  Future<Map<String, dynamic>> createVariantGroup(
      Map<String, dynamic> data) async {
    createdGroupPayload = data;
    return {'id': 'g1', 'name': data['name']};
  }

  @override
  Future<List<Map<String, dynamic>>> generateVariantCombinations(
      String groupId, Map<String, dynamic> data) async {
    generatedGroupId = groupId;
    generatedPayload = data;
    return [
      {'id': 'p1'},
      {'id': 'p2'},
    ];
  }
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('crea el grupo y genera combinaciones con el precio/stock base',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(
      home: CreateVariantGroupScreen(apiOverride: api),
    ));

    await tester.enterText(
        find.byKey(const Key('variant_group_name')), 'Camiseta Básica');
    await tester.enterText(
        find.byKey(const Key('variant_group_price')), '20000');
    await tester.enterText(
        find.byKey(const Key('variant_group_stock')), '5');

    await tester.enterText(
        find.byKey(const Key('variant_attr_label_0')), 'Talla');
    await tester.enterText(
        find.byKey(const Key('variant_attr_values_0')), 'S,M');
    await tester.pump();

    await tester.tap(find.byKey(const Key('variant_generate_button')));
    await tester.pumpAndSettle();

    expect(api.createdGroupPayload?['name'], 'Camiseta Básica');
    expect(api.generatedGroupId, 'g1');
    expect(api.generatedPayload?['attributes'], {
      'Talla': ['S', 'M'],
    });
    expect(api.generatedPayload?['base_price'], 20000.0);
    expect(api.generatedPayload?['base_stock'], 5);
  });
}
