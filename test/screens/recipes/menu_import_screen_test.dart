// Spec: specs/043-menu-restaurante-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/recipes/menu_import_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — descripción + foto fijas para el plato.
class _FakeMenuApi extends ApiService {
  _FakeMenuApi(this._desc, {String? imageUrl})
      : _imageUrl = imageUrl,
        super(AuthService());
  final String _desc;
  final String? _imageUrl;

  @override
  Future<String> generateMenuDescription({
    required String name,
    String category = '',
  }) async =>
      _desc;

  @override
  Future<String> generateMenuImage({
    required String name,
    String category = '',
  }) async =>
      _imageUrl ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  group('EditableDish (F043)', () {
    test('fromScan mapea los campos del plato escaneado', () {
      final d = EditableDish.fromScan({
        'name': 'Bandeja Paisa',
        'description': 'Frijoles, arroz, carne',
        'price': 25000,
        'portion': 'Personal',
        'category': 'Platos fuertes',
      });

      expect(d.name.text, 'Bandeja Paisa');
      expect(d.description.text, 'Frijoles, arroz, carne');
      expect(d.price.text, '25000');
      expect(d.portion.text, 'Personal');
      expect(d.category, 'Platos fuertes');
      expect(d.isValid, isTrue);
    });

    test('fromScan sin categoría cae a "Platos fuertes" y precio 0 → vacío', () {
      final d = EditableDish.fromScan({'name': 'Algo', 'price': 0});
      expect(d.category, 'Platos fuertes');
      expect(d.price.text, '');
    });

    test('toCreatePayload marca is_menu_item y omite campos vacíos', () {
      final d = EditableDish.fromScan({
        'name': 'Limonada',
        'description': '',
        'price': 8000,
        'portion': '',
        'category': 'Bebidas',
      });
      final payload = d.toCreatePayload();

      expect(payload['name'], 'Limonada');
      expect(payload['price'], 8000);
      expect(payload['is_menu_item'], true);
      expect(payload['category'], 'Bebidas');
      expect(payload['stock'], 0);
      expect(payload.containsKey('description'), isFalse);
      expect(payload.containsKey('portion'), isFalse);
    });

    test('isValid exige al menos 2 letras en el nombre', () {
      expect(EditableDish.fromScan({'name': 'A'}).isValid, isFalse);
      expect(EditableDish.fromScan({'name': ''}).isValid, isFalse);
      expect(EditableDish.fromScan({'name': 'Te'}).isValid, isTrue);
    });
  });

  group('MenuImportScreen (F043)', () {
    testWidgets('renderiza los platos escaneados con sus campos editables',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MenuImportScreen(scannedDishes: [
          {
            'name': 'Bandeja Paisa',
            'description': 'Frijoles y arroz',
            'price': 25000,
            'portion': 'Personal',
            'category': 'Platos fuertes',
          },
        ]),
      ));
      await tester.pump();

      expect(find.text('Bandeja Paisa'), findsOneWidget);
      expect(find.text('Frijoles y arroz'), findsOneWidget);
      expect(find.byKey(const Key('menu_import_save')), findsOneWidget);
      expect(find.byKey(const Key('menu_import_add')), findsOneWidget);
    });

    testWidgets('agregar plato añade una tarjeta vacía', (tester) async {
      // Lienzo alto para que la ListView construya ambas tarjetas (la 2ª
      // queda fuera del viewport por defecto y la lista las construye perezoso).
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(
        home: MenuImportScreen(scannedDishes: [
          {'name': 'Plato 1', 'price': 1000, 'category': 'Otros'},
        ]),
      ));
      await tester.pump();

      // 1 tarjeta inicial → un botón de borrar.
      expect(find.byKey(const Key('menu_dish_remove_0')), findsOneWidget);
      expect(find.byKey(const Key('menu_dish_remove_1')), findsNothing);

      await tester.tap(find.byKey(const Key('menu_import_add')));
      await tester.pump();

      expect(find.byKey(const Key('menu_dish_remove_1')), findsOneWidget);
    });

    testWidgets('lista vacía arranca con una tarjeta para llenar a mano',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MenuImportScreen(scannedDishes: []),
      ));
      await tester.pump();

      expect(find.byKey(const Key('menu_dish_remove_0')), findsOneWidget);
    });

    testWidgets('"Descripción con IA" llena el campo con la IA (F043)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(
          apiOverride: _FakeMenuApi('Frijoles, arroz, carne y chicharrón'),
          scannedDishes: const [
            {'name': 'Bandeja Paisa', 'price': 25000, 'category': 'Platos fuertes'},
          ],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('menu_dish_ai_desc_0')));
      await tester.pump(); // dispara la llamada (loading)
      await tester.pumpAndSettle();

      expect(find.text('Frijoles, arroz, carne y chicharrón'), findsOneWidget);
    });

    testWidgets('"Foto con IA" genera y muestra la miniatura de muestra (F043)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(
          apiOverride: _FakeMenuApi('',
              imageUrl: 'https://r2.vendia.co/menu/abc.png'),
          scannedDishes: const [
            {'name': 'Bandeja Paisa', 'price': 25000},
          ],
        ),
      ));
      await tester.pump();

      // Estado inicial: botón para generar.
      expect(find.byKey(const Key('menu_dish_ai_photo_0')), findsOneWidget);
      expect(find.text('Muestra'), findsNothing);

      await tester.tap(find.byKey(const Key('menu_dish_ai_photo_0')));
      await tester.pump();
      await tester.pumpAndSettle();

      // Tras generar: aparece la miniatura con el badge "Muestra".
      expect(find.text('Muestra'), findsOneWidget);
      expect(find.textContaining('Cambiar foto'), findsOneWidget);
    });
  });
}
