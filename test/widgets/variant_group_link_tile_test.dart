// Spec: specs/095-variantes-producto/spec.md (AC-03)
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/variant_group_link_tile.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._groups) : super(AuthService());
  final List<Map<String, dynamic>> _groups;
  Map<String, dynamic>? adoptedWith;

  @override
  Future<List<Map<String, dynamic>>> listVariantGroups() async => _groups;

  @override
  Future<Map<String, dynamic>> adoptProductToVariantGroup(
      String productId, Map<String, dynamic> data) async {
    adoptedWith = {'productId': productId, ...data};
    return {'id': productId, 'variant_group_id': data['variant_group_id']};
  }
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('sin grupo vinculado, ofrece elegir uno y adoptar (AC-03)',
      (tester) async {
    final api = _FakeApi([
      {'id': 'g1', 'name': 'Camiseta Básica'},
      {'id': 'g2', 'name': 'Pantalón'},
    ]);
    bool adopted = false;
    await tester.pumpWidget(wrap(VariantGroupLinkTile(
      apiOverride: api,
      productId: 'p1',
      currentGroupId: null,
      onAdopted: () => adopted = true,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Vincular a un grupo de variantes'), findsOneWidget);
    await tester.tap(find.text('Vincular a un grupo de variantes'));
    await tester.pumpAndSettle();

    expect(find.text('Camiseta Básica'), findsOneWidget);
    await tester.tap(find.text('Camiseta Básica'));
    await tester.pumpAndSettle();

    expect(api.adoptedWith?['productId'], 'p1');
    expect(api.adoptedWith?['variant_group_id'], 'g1');
    expect(adopted, isTrue);
  });

  testWidgets('con grupo ya vinculado, muestra "Parte de: <grupo>"',
      (tester) async {
    final api = _FakeApi([
      {'id': 'g1', 'name': 'Camiseta Básica'},
    ]);
    await tester.pumpWidget(wrap(VariantGroupLinkTile(
      apiOverride: api,
      productId: 'p1',
      currentGroupId: 'g1',
      onAdopted: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Camiseta Básica'), findsOneWidget);
    expect(find.text('Vincular a un grupo de variantes'), findsNothing);
  });
}
