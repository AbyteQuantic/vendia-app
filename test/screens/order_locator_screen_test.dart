// Spec: specs/105-hito-restaurante-comandas/spec.md — F4 (QR localizador).
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:vendia_pos/screens/pos/order_locator_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  final String baseUrl = 'https://tienda.vendia.store/brasas';
  bool fail = false;

  @override
  Future<Map<String, dynamic>> fetchStoreSlug() async {
    if (fail) throw Exception('sin red');
    return {'base_url': baseUrl};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  Widget app(_FakeApi api) => MaterialApp(
        home: OrderLocatorScreen(
          orderLabel: 'Pedido 7',
          sessionToken: 'tok-123',
          apiOverride: api,
        ),
      );

  testWidgets('muestra el número GIGANTE, el QR y el botón de WhatsApp',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(app(api));
    await tester.pump();

    // El número de pedido ES el feature (40-60% no escanea el QR).
    expect(find.text('Pedido 7'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('WhatsApp'), findsOneWidget);
    expect(find.text('Entendido'), findsOneWidget);
  });

  testWidgets('la URL del QR apunta a /t/{token} del dominio público',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(app(api));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('qr:https://tienda.vendia.store/t/tok-123')),
      findsOneWidget,
    );
  });

  testWidgets('sin red: el número gigante sigue sirviendo (QR se omite)',
      (tester) async {
    final api = _FakeApi()..fail = true;
    await tester.pumpWidget(app(api));
    await tester.pump();

    expect(find.text('Pedido 7'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    // Copy honesto: el cajero canta el número.
    expect(find.textContaining('cante el número'), findsOneWidget);
  });
}
