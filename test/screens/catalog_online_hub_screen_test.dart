// Spec: specs/061-catalogo-online-hub/spec.md

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/online_store/catalog_online_hub_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._url) : super(AuthService());
  final String? _url;

  @override
  Future<Map<String, dynamic>> fetchStoreSlug() async => {
        'slug': 'mi-tienda',
        'base_url': 'https://tienda.vendia.store',
        'public_url': _url,
      };
}

Future<void> _pump(WidgetTester tester, String? url) async {
  await tester.pumpWidget(MaterialApp(
    home: CatalogOnlineHubScreen(apiOverride: _FakeApi(url)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('con link: muestra URL, vista previa, compartir y copiar',
      (tester) async {
    await _pump(tester, 'https://tienda.vendia.store/mi-tienda');

    expect(find.byKey(const Key('catalog_hub_url')), findsOneWidget);
    expect(find.text('https://tienda.vendia.store/mi-tienda'), findsOneWidget);
    expect(find.byKey(const Key('catalog_hub_preview')), findsOneWidget);
    expect(find.byKey(const Key('catalog_hub_share')), findsOneWidget);
    expect(find.byKey(const Key('catalog_hub_copy')), findsOneWidget);
  });

  testWidgets('reúne acciones: campañas masivas y editar banner',
      (tester) async {
    await _pump(tester, 'https://tienda.vendia.store/mi-tienda');
    expect(find.text('Envío masivo por campañas'), findsOneWidget);
    expect(find.text('Editar banner y promociones'), findsOneWidget);
  });

  testWidgets('sin link configurado → muestra guía, no botones de link',
      (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('catalog_hub_preview')), findsNothing);
    expect(find.textContaining('Configure el enlace'), findsOneWidget);
  });
}
