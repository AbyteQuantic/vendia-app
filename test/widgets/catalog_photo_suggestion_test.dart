// Spec: specs/096-foto-referencia-verificada/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/catalog_photo_suggestion.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._result) : super(AuthService());
  final Map<String, dynamic>? _result;

  @override
  Future<Map<String, dynamic>?> fetchCatalogReferencePhoto(
      String barcode) async => _result;
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('sin foto de referencia, no muestra nada (AC-04)',
      (tester) async {
    final api = _FakeApi(null);
    await tester.pumpWidget(wrap(CatalogPhotoSuggestion(
      apiOverride: api,
      barcode: '0000000000000',
      onAccept: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CatalogPhotoSuggestion), findsOneWidget);
    expect(find.textContaining('Encontramos una foto'), findsNothing);
  });

  testWidgets('con foto de referencia, muestra la sugerencia (AC-01)',
      (tester) async {
    final api = _FakeApi({
      'catalog_product_id': 'cp1',
      'image_url': 'https://off.example/coca.jpg',
      'brand': 'Coca-Cola',
      'name': 'Coca-Cola 400ml',
    });
    await tester.pumpWidget(wrap(CatalogPhotoSuggestion(
      apiOverride: api,
      barcode: '7702090000012',
      onAccept: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Encontramos una foto'), findsOneWidget);
  });

  testWidgets(
      'tocar "Ver foto" abre el aviso de catálogo público antes de aplicar (AC-02)',
      (tester) async {
    final api = _FakeApi({
      'catalog_product_id': 'cp1',
      'image_url': 'https://off.example/coca.jpg',
      'brand': 'Coca-Cola',
      'name': 'Coca-Cola 400ml',
    });
    await tester.pumpWidget(wrap(CatalogPhotoSuggestion(
      apiOverride: api,
      barcode: '7702090000012',
      onAccept: (_) {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver foto'));
    await tester.pumpAndSettle();

    expect(find.textContaining('catálogo público'), findsOneWidget);
    expect(find.text('Usar esta foto'), findsOneWidget);
    expect(find.text('Tomar la mía'), findsOneWidget);
  });

  testWidgets('"Usar esta foto" invoca onAccept con la URL (AC-03)',
      (tester) async {
    final api = _FakeApi({
      'catalog_product_id': 'cp1',
      'image_url': 'https://off.example/coca.jpg',
      'brand': 'Coca-Cola',
      'name': 'Coca-Cola 400ml',
    });
    String? acceptedUrl;
    await tester.pumpWidget(wrap(CatalogPhotoSuggestion(
      apiOverride: api,
      barcode: '7702090000012',
      onAccept: (url) => acceptedUrl = url,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar esta foto'));
    await tester.pumpAndSettle();

    expect(acceptedUrl, 'https://off.example/coca.jpg');
  });

  testWidgets('"No, gracias" cierra sin invocar onAccept (AC-04)',
      (tester) async {
    final api = _FakeApi({
      'catalog_product_id': 'cp1',
      'image_url': 'https://off.example/coca.jpg',
      'brand': 'Coca-Cola',
      'name': 'Coca-Cola 400ml',
    });
    bool accepted = false;
    await tester.pumpWidget(wrap(CatalogPhotoSuggestion(
      apiOverride: api,
      barcode: '7702090000012',
      onAccept: (_) => accepted = true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No, gracias'));
    await tester.pumpAndSettle();

    expect(accepted, isFalse);
    expect(find.textContaining('Encontramos una foto'), findsNothing);
  });

  testWidgets('"Tomar la mía" cierra el aviso sin invocar onAccept',
      (tester) async {
    final api = _FakeApi({
      'catalog_product_id': 'cp1',
      'image_url': 'https://off.example/coca.jpg',
      'brand': 'Coca-Cola',
      'name': 'Coca-Cola 400ml',
    });
    bool accepted = false;
    await tester.pumpWidget(wrap(CatalogPhotoSuggestion(
      apiOverride: api,
      barcode: '7702090000012',
      onAccept: (_) => accepted = true,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomar la mía'));
    await tester.pumpAndSettle();

    expect(accepted, isFalse);
  });
}
