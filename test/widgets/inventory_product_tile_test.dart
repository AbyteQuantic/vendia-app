// Rediseño "Mi Inventario" (2026-07-08, feedback del fundador): el tile de
// producto pasa de tarjeta gigante (~1/3 de pantalla, 3 IconButtons en
// columna) a FILA COMPACTA: miniatura 56dp + nombre a 2 líneas + fila
// precio/tag/StockBadge + SOLO 2 controles (Editar visible ≥44dp y menú ⋮
// con Historial/Eliminar). Eliminar deja de estar a un toque accidental
// (audiencia 50+) pero sigue funcionando vía menú, con el diálogo de
// confirmación intacto en la pantalla.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/theme/app_theme.dart';
import 'package:vendia_pos/widgets/inventory_product_tile.dart';

Map<String, dynamic> _p(
  String id,
  String name, {
  num price = 5500,
  int stock = 12,
  String barcode = '',
  String presentation = '',
  String content = '',
}) =>
    {
      'id': id,
      'name': name,
      'price': price,
      'stock': stock,
      'barcode': barcode,
      'presentation': presentation,
      'content': content,
      'photo_url': '',
      'image_url': '',
    };

Future<void> _pumpTile(
  WidgetTester tester,
  Map<String, dynamic> product, {
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  VoidCallback? onHistory,
}) {
  return tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ListView(children: [
        InventoryProductTile(
          product: product,
          onEdit: onEdit ?? () {},
          onDelete: onDelete ?? () {},
          onHistory: onHistory,
        ),
      ]),
    ),
  ));
}

class _FakeApi extends ApiService {
  _FakeApi(this._products) : super(AuthService());
  final List<Map<String, dynamic>> _products;

  @override
  Future<List<Map<String, dynamic>>> fetchAllProducts(
      {String? branchId, bool sellableOnly = false}) async {
    return _products;
  }
}

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  group('InventoryProductTile — tile compacto', () {
    testWidgets(
        'a 360dp con nombre y precio largos: sin overflow y altura compacta',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpTile(
        tester,
        _p(
          '1',
          'Frijoles con pollo desmechado y plátano maduro tamaño familiar',
          price: 12345678,
          stock: 0,
          presentation: 'paquete',
          content: '1000g',
        ),
      );

      expect(tester.takeException(), isNull);
      // Compacto de verdad: fila ~92dp, no la tarjeta de ~1/3 de pantalla.
      final height = tester.getSize(find.byType(InventoryProductTile)).height;
      expect(height, lessThanOrEqualTo(112));
      // El nombre puede usar hasta 2 líneas con ellipsis (antes 1).
      final nameText = tester.widget<Text>(
          find.textContaining('Frijoles con pollo'));
      expect(nameText.maxLines, 2);
      expect(nameText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('Editar es la acción principal visible con objetivo ≥44dp',
        (tester) async {
      var edited = false;
      await _pumpTile(tester, _p('1', 'Arroz Diana'),
          onEdit: () => edited = true);

      final editBtn = find.widgetWithIcon(IconButton, Icons.edit_rounded);
      expect(editBtn, findsOneWidget);
      final size = tester.getSize(editBtn);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));

      await tester.tap(editBtn);
      expect(edited, isTrue);
    });

    testWidgets(
        'Eliminar YA NO es un botón directo: vive en el menú ⋮ y sigue '
        'disparando onDelete', (tester) async {
      var deleted = false;
      var history = false;
      await _pumpTile(tester, _p('1', 'Arroz Diana'),
          onDelete: () => deleted = true, onHistory: () => history = true);

      // Sin botón directo de eliminar sobre la fila.
      expect(find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
          findsNothing);
      expect(find.text('Eliminar'), findsNothing);

      // El menú ⋮ agrupa Historial y Eliminar.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Historial'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(history, isFalse);
    });

    testWidgets('Historial funciona vía menú ⋮', (tester) async {
      var history = false;
      await _pumpTile(tester, _p('1', 'Arroz Diana'),
          onHistory: () => history = true);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(history, isTrue);
    });

    testWidgets('sin onHistory el menú solo ofrece Eliminar', (tester) async {
      await _pumpTile(tester, _p('1', 'Arroz Diana'));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Historial'), findsNothing);
      expect(find.text('Eliminar'), findsOneWidget);
    });

    testWidgets('el tag muestra presentación · contenido (o SKU corto)',
        (tester) async {
      await _pumpTile(tester,
          _p('1', 'Coca-Cola', presentation: 'botella', content: '350ml'));
      expect(find.text('botella · 350ml'), findsOneWidget);

      await _pumpTile(tester, _p('2', 'Panela', barcode: '7702004003508'));
      expect(find.text('SKU 7702004003508'), findsOneWidget);
    });
  });

  group('ManageInventoryScreen — eliminar conserva su confirmación', () {
    testWidgets(
        'menú ⋮ → Eliminar abre el diálogo de confirmación de la pantalla',
        (tester) async {
      final api = _FakeApi([_p('1', 'Arroz Diana', barcode: '111')]);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: ManageInventoryScreen(apiOverride: api)));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar producto'), findsOneWidget);
      expect(find.textContaining('¿Seguro que desea eliminar'),
          findsOneWidget);
    });
  });
}
