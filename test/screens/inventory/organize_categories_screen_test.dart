// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/inventory/organize_categories_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>>? saved;
  @override
  Future<List<Map<String, dynamic>>> suggestProductCategories() async => [
        {'id': 'p1', 'name': 'Lubricante Neutro', 'suggested': 'Lubricantes'},
        {'id': 'p2', 'name': 'Perfume Dama', 'suggested': 'Perfumes'},
      ];
  @override
  Future<int> bulkUpdateCategories(List<Map<String, dynamic>> items) async {
    saved = items;
    return items.length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('IA sugiere categorías, el tenant edita una y guarda', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: OrganizeCategoriesScreen(api: api)));
    await tester.pumpAndSettle();

    // Sugerencias pre-cargadas y editables.
    expect(find.text('Lubricante Neutro'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Lubricantes'), findsOneWidget);

    // El tenant edita la categoría de p2.
    await tester.enterText(find.byKey(const Key('cat_p2')), 'Fragancias');
    await tester.tap(find.byKey(const Key('save_categories')));
    await tester.pumpAndSettle();

    expect(api.saved, isNotNull);
    expect(api.saved!.firstWhere((e) => e['id'] == 'p1')['category'], 'Lubricantes');
    expect(api.saved!.firstWhere((e) => e['id'] == 'p2')['category'], 'Fragancias'); // editado
  });
}
