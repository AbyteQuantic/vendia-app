// Spec: specs/061-catalogo-online-hub/spec.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/online_store/catalog_online_hub_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

// Spec 084 — el hub ahora lee enable_staff_commissions; sin este mock el
// method channel de secure storage cuelga el pumpAndSettle.
const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null; // sin flags → enableStaffCommissions=false
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
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

  testWidgets('reúne acciones: personalizar, campañas y promociones',
      (tester) async {
    await _pump(tester, 'https://tienda.vendia.store/mi-tienda');
    expect(find.text('Nombre, eslogan y color de marca'), findsOneWidget);
    expect(find.text('Envío masivo por campañas'), findsOneWidget);
    expect(find.text('Promociones y combos'), findsOneWidget);
  });

  // Spec 083 — la opción de configurar mesas + QR DEBE estar visible en el hub
  // (regresión: antes quedó enterrada dentro de "Nombre, eslogan...").
  testWidgets('muestra la opción "Mesas y código QR"', (tester) async {
    await _pump(tester, 'https://tienda.vendia.store/mi-tienda');
    expect(find.text('Mesas y código QR'), findsOneWidget);
  });

  testWidgets('sin link configurado → muestra guía, no botones de link',
      (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('catalog_hub_preview')), findsNothing);
    expect(find.textContaining('Configure el enlace'), findsOneWidget);
  });
}
