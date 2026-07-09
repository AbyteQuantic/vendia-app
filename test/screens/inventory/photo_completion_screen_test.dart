// Spec: specs/097-completar-fotos-inventario/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/catalog_suggestion.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/inventory/photo_completion_screen.dart';
import 'package:vendia_pos/theme/app_theme.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._suggestions) : super(AuthService());
  final Map<String, CatalogSuggestion> _suggestions;
  final List<MapEntry<String, Map<String, dynamic>>> patched = [];

  @override
  Future<Map<String, CatalogSuggestion>> fetchCatalogReferencePhotos(
      List<String> barcodes) async {
    return {
      for (final b in barcodes)
        if (_suggestions.containsKey(b)) b: _suggestions[b]!,
    };
  }

  @override
  Future<Map<String, dynamic>> updateProduct(
      String id, Map<String, dynamic> data) async {
    patched.add(MapEntry(id, data));
    return {'id': id, ...data};
  }
}

Map<String, dynamic> _p(String id, String name, {String barcode = ''}) => {
      'id': id,
      'name': name,
      'barcode': barcode,
      'photo_url': '',
      'image_url': '',
    };

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  // Theme REAL de la app: el theme legacy de botones (64dp/22px) queda bajo
  // prueba y las acciones compactas no pueden regresar a botones gigantes.
  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  testWidgets('muestra sugerencia verificada y sin confirmar', (tester) async {
    final api = _FakeApi({
      '111': const CatalogSuggestion(
          imageUrl: 'https://r2/a.jpg', name: 'A', verified: true),
      '222': const CatalogSuggestion(
          imageUrl: 'https://off/b.jpg', name: 'B', verified: false),
    });
    await tester.pumpWidget(wrap(PhotoCompletionScreen(
      apiOverride: api,
      products: [_p('1', 'Coca', barcode: '111'), _p('2', 'Salsa', barcode: '222')],
    )));
    await tester.pump(); // corre el fetch de sugerencias
    await tester.pump();

    expect(find.text('Verificada'), findsOneWidget);
    expect(find.text('Sin confirmar'), findsOneWidget);
    expect(find.text('0 de 2 con foto'), findsOneWidget);
    // Botón de aplicar todas con el conteo de pendientes.
    expect(find.textContaining('Usar todas las sugeridas (2)'), findsOneWidget);
  });

  testWidgets('"Usar" aplica la foto (PATCH image_url) y marca Lista',
      (tester) async {
    final api = _FakeApi({
      '111': const CatalogSuggestion(
          imageUrl: 'https://r2/a.jpg', name: 'A', verified: true),
    });
    await tester.pumpWidget(wrap(PhotoCompletionScreen(
      apiOverride: api,
      products: [_p('1', 'Coca', barcode: '111')],
    )));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Usar'));
    await tester.pump(); // resuelve updateProduct
    await tester.pump();

    expect(api.patched.length, 1);
    expect(api.patched.first.key, '1');
    expect(api.patched.first.value['image_url'], 'https://r2/a.jpg');
    expect(find.text('Lista'), findsOneWidget);
    expect(find.text('1 de 1 con foto'), findsOneWidget);
  });

  testWidgets('"No" descarta la sugerencia sin tocar el producto',
      (tester) async {
    final api = _FakeApi({
      '111': const CatalogSuggestion(
          imageUrl: 'https://r2/a.jpg', name: 'A', verified: true),
    });
    await tester.pumpWidget(wrap(PhotoCompletionScreen(
      apiOverride: api,
      products: [_p('1', 'Coca', barcode: '111')],
    )));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('No'));
    await tester.pump();

    expect(api.patched, isEmpty);
    expect(find.text('Verificada'), findsNothing); // sugerencia oculta
    // Sigue ofreciendo acciones manuales.
    expect(find.text('Crear IA'), findsOneWidget);
  });

  testWidgets('sin barcode → sin sugerencia, solo acciones manuales',
      (tester) async {
    final api = _FakeApi(const {});
    await tester.pumpWidget(wrap(PhotoCompletionScreen(
      apiOverride: api,
      products: [_p('1', 'Producto suelto')],
    )));
    await tester.pump();
    await tester.pump();

    expect(find.text('Usar'), findsNothing);
    // Las 4 opciones pedidas SIEMPRE visibles por tarjeta.
    expect(find.text('Crear IA'), findsOneWidget);
    expect(find.text('Cargar'), findsOneWidget);
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Recortar fondo'), findsOneWidget);
  });

  testWidgets('"Usar todas las sugeridas" aplica en lote', (tester) async {
    final api = _FakeApi({
      '111': const CatalogSuggestion(imageUrl: 'https://r2/a.jpg', verified: true),
      '222': const CatalogSuggestion(imageUrl: 'https://off/b.jpg', verified: false),
    });
    await tester.pumpWidget(wrap(PhotoCompletionScreen(
      apiOverride: api,
      products: [_p('1', 'A', barcode: '111'), _p('2', 'B', barcode: '222')],
    )));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.textContaining('Usar todas las sugeridas'));
    await tester.pump();
    await tester.pump();

    expect(api.patched.length, 2);
    expect(find.text('2 de 2 con foto'), findsOneWidget);
  });

  testWidgets('UI normalizada: a 360dp cero overflow y acciones compactas '
      'con tap target ≥ 44dp (nombre largo)', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi({});
    await tester.pumpWidget(wrap(PhotoCompletionScreen(
      apiOverride: api,
      products: [
        _p('1', 'Chocolatina de maní con leche entera edición especial 500 g'),
      ],
    )));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull); // cero overflow a 360dp

    // Acciones compactas que COMPARTEN renglón (antes: apiladas full-width,
    // una por línea). El Wrap fluye según el ancho real; con la fuente de
    // prueba (Ahem, más ancha) al menos las 2 primeras van juntas.
    final dyIa = tester.getCenter(find.text('Crear IA')).dy;
    final dyCargar = tester.getCenter(find.text('Cargar')).dy;
    expect(dyCargar, moreOrLessEquals(dyIa, epsilon: 1.0));

    // Tap target ≥ 44dp y nada de botones full-width del theme legacy.
    final btn = find
        .ancestor(
            of: find.text('Crear IA'), matching: find.byType(OutlinedButton))
        .first;
    expect(tester.getSize(btn).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(btn).width, lessThan(200));
  });
}
