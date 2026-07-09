// Pedido del fundador 2026-07-09: la fila de resumen/filtros de Mi Inventario
// (pill "N productos" + chips de curaduría) es un CARRUSEL horizontal de UNA
// sola línea — el Wrap partía en 2-3 líneas a 360dp y se comía el espacio
// vertical de la lista en móvil. Los chips que no caben se descubren
// deslizando; cada chip conserva su estilo/altura/lógica.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/theme/app_theme.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._products) : super(AuthService());
  final List<Map<String, dynamic>> _products;

  @override
  Future<List<Map<String, dynamic>>> fetchAllProducts(
      {String? branchId, bool sellableOnly = false}) async {
    return _products;
  }

  @override
  Future<Map<String, dynamic>> fetchRetouchSummary(
      {int page = 1, int perPage = 100}) async {
    return const {
      'eligible_count': 1,
      'active_batch': null,
      'review_items': <Map<String, dynamic>>[],
    };
  }
}

/// Producto "completo" por defecto; cada flag de curaduría se dispara con un
/// override puntual para que cada chip cuente exactamente 1.
Map<String, dynamic> _p(
  String id,
  String name, {
  num price = 1000,
  String barcode = '111',
  String category = 'Bebidas',
  String photoUrl = 'https://cdn.example/catalog/x.jpg',
}) =>
    {
      'id': id,
      'name': name,
      'price': price,
      'stock': 5,
      'barcode': barcode,
      'category': category,
      'photo_url': photoUrl,
      'image_url': '',
    };

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  final products = [
    _p('1', 'Arroz Diana', price: 0), // → Sin precio (1)
    _p('2', 'Panela', barcode: ''), // → Sin SKU (1)
    _p('3', 'Coca-Cola', category: ''), // → Sin categoría (1)
    // Foto propia cruda (products/<tenant>/…, sin -enhanced/-generated)
    // → Fotos sin retocar (1).
    _p('4', 'Empanada', photoUrl: 'https://cdn.example/products/t1/e.jpg'),
  ];

  const labels = [
    '4 productos',
    'Sin precio (1)',
    'Sin SKU (1)',
    'Fotos sin retocar (1)',
    'Sin categoría (1)',
  ];

  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(ManageInventoryScreen(
      apiOverride: _FakeApi(products),
      tenantIdOverride: 't1',
    )));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'a 360dp con los 5 pills presentes: UNA sola línea (mismo dy) '
      'y sin overflow', (tester) async {
    await pumpScreen(tester);

    // Sin excepción de overflow al montar a 360dp.
    expect(tester.takeException(), isNull);

    // Los 5 pills existen y comparten renglón (mismo centro vertical).
    final dys = <double>[];
    for (final label in labels) {
      final text = find.text(label);
      expect(text, findsOneWidget, reason: 'falta el pill "$label"');
      dys.add(tester.getCenter(text).dy);
    }
    for (final dy in dys) {
      expect(dy, moreOrLessEquals(dys.first, epsilon: 0.5),
          reason: 'los pills deben quedar en UNA sola línea (carrusel), '
              'no envueltos en varias: $dys');
    }
  });

  testWidgets('el carrusel desliza horizontal y alcanza el último chip',
      (tester) async {
    await pumpScreen(tester);

    final carousel = find.byKey(const Key('inventory_filter_carousel'));
    expect(carousel, findsOneWidget);

    // Con 5 pills a 360dp el último queda fuera del viewport…
    final lastBefore = tester.getCenter(find.text(labels.last));
    expect(lastBefore.dx, greaterThan(360),
        reason: 'el último chip debe empezar fuera de pantalla a 360dp');

    // …y deslizando el carrusel se descubre (drags cortos: un drag largo
    // sacaría el puntero de una pantalla de 360dp).
    for (var i = 0;
        i < 12 && tester.getCenter(find.text(labels.last)).dx > 340;
        i++) {
      await tester.drag(carousel, const Offset(-120, 0));
      await tester.pump();
    }

    final lastAfter = tester.getCenter(find.text(labels.last));
    expect(lastAfter.dx, lessThan(360));
    expect(lastAfter.dx, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
