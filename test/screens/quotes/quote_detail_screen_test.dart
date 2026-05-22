// Spec: specs/031-cotizaciones/spec.md
//
// T-38 — Widget test de QuoteDetailScreen.
// Cobertura:
//   - "Enviar" aparece solo cuando el estado es `borrador`.
//   - "Convertir en venta" aparece solo cuando el estado es `aprobada`.
//   - "Editar" aparece en `borrador`/`enviada` y no en estados cerrados.
//   - el detalle pinta folio, cliente, items y totales.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/quotes/quote_detail_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — devuelve una cotización con el estado pedido.
class _FakeQuotesApi extends ApiService {
  _FakeQuotesApi(this._status) : super(AuthService());

  final String _status;

  @override
  Future<Map<String, dynamic>> getQuote(String id) async {
    return {
      'id': id,
      'folio': 'COT-2026-0001',
      'status': _status,
      'customer_id': 'c-acme',
      'customer_name': 'Constructora ACME',
      'items': [
        {
          'product_id': 'p-cemento',
          'name': 'Cemento gris',
          'quantity': 2,
          'unit_price': 25000,
          'discount': 0,
          'subtotal': 50000,
        },
      ],
      'discount_total': 0,
      'tax_rate': 0,
      'subtotal': 50000,
      'tax_amount': 0,
      'total': 50000,
      'public_token': 'tok-123',
    };
  }

  @override
  Future<Map<String, dynamic>> fetchStoreSlug() async {
    return {'base_url': 'https://tienda.vendia.store/demo'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  Future<void> pump(WidgetTester tester, String status) async {
    await tester.pumpWidget(MaterialApp(
      home: QuoteDetailScreen(
        quoteId: 'q-1',
        apiOverride: _FakeQuotesApi(status),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('QuoteDetailScreen (F031)', () {
    testWidgets('pinta folio, cliente, items y totales', (tester) async {
      await pump(tester, 'borrador');

      expect(find.text('COT-2026-0001'), findsWidgets);
      expect(find.text('Constructora ACME'), findsOneWidget);
      expect(find.text('Cemento gris'), findsOneWidget);
      expect(find.textContaining('50.000'), findsWidgets);
    });

    testWidgets('en borrador muestra "Enviar" y no "Convertir"',
        (tester) async {
      await pump(tester, 'borrador');

      expect(find.byKey(const Key('quote_detail_send')), findsOneWidget);
      expect(find.byKey(const Key('quote_detail_convert')), findsNothing);
      // Editable en borrador.
      expect(find.byKey(const Key('quote_detail_edit')), findsOneWidget);
    });

    testWidgets('en enviada no muestra "Enviar" pero sí "Reenviar"',
        (tester) async {
      await pump(tester, 'enviada');

      expect(find.byKey(const Key('quote_detail_send')), findsNothing);
      expect(find.byKey(const Key('quote_detail_resend')), findsOneWidget);
      expect(find.byKey(const Key('quote_detail_convert')), findsNothing);
      // Editable en enviada (genera V2).
      expect(find.byKey(const Key('quote_detail_edit')), findsOneWidget);
    });

    testWidgets('en aprobada muestra "Convertir en venta"',
        (tester) async {
      await pump(tester, 'aprobada');

      expect(find.byKey(const Key('quote_detail_convert')), findsOneWidget);
      expect(find.byKey(const Key('quote_detail_send')), findsNothing);
      // Aprobada no es editable.
      expect(find.byKey(const Key('quote_detail_edit')), findsNothing);
    });

    testWidgets('en convertida no muestra acciones contextuales',
        (tester) async {
      await pump(tester, 'convertida');

      expect(find.byKey(const Key('quote_detail_send')), findsNothing);
      expect(find.byKey(const Key('quote_detail_convert')), findsNothing);
      expect(find.byKey(const Key('quote_detail_resend')), findsNothing);
      expect(find.byKey(const Key('quote_detail_edit')), findsNothing);
    });
  });
}
