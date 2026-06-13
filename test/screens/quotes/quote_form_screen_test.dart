// Spec: specs/031-cotizaciones/spec.md
//
// T-34 — Widget test de QuoteFormScreen.
// Cobertura:
//   - crear una cotización con 1 producto del inventario + 1 línea
//     libre llama a `createQuote` con el payload correcto.
//   - guardar sin cliente muestra un error y NO llama a createQuote.
//   - los totales en vivo reflejan las líneas agregadas.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/quotes/quote_form_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/tax_settings_service.dart';

/// Doble de ApiService — captura el payload de [createQuote] y sirve
/// fixtures fijas para clientes y productos. Cualquier endpoint ajeno
/// queda sin implementar para que una regresión salte.
class _FakeQuotesApi extends ApiService {
  _FakeQuotesApi() : super(AuthService());

  Map<String, dynamic>? capturedCreatePayload;
  int createCalls = 0;

  @override
  Future<Map<String, dynamic>> listCustomers({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    return {
      'data': [
        {'id': 'c-acme', 'name': 'Constructora ACME', 'phone': '3001112233'},
      ],
      'meta': {'total': 1, 'limit': limit, 'offset': offset},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchProducts({
    int page = 1,
    int perPage = 20,
    String? branchId,
  }) async {
    return {
      'data': [
        {'id': 'p-cemento', 'name': 'Cemento gris', 'price': 25000, 'stock': 50},
      ],
      'meta': {'total': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> createQuote(Map<String, dynamic> data) async {
    createCalls++;
    capturedCreatePayload = data;
    return {
      'id': 'q-new',
      'folio': 'COT-2026-0001',
      'status': 'borrador',
      'customer_id': data['customer_id'],
      'items': data['items'],
      'discount_total': data['discount_total'],
      'tax_rate': data['tax_rate'],
      'subtotal': 50000,
      'tax_amount': 0,
      'total': 50000,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  tearDown(TaxSettingsService.debugResetInstance);

  Future<void> pump(WidgetTester tester, ApiService api) async {
    // F023 OFF para el test base — la sección de IVA no aparece.
    final tax = TaxSettingsService.instance;
    await tester.pumpWidget(MaterialApp(
      home: QuoteFormScreen(apiOverride: api, taxServiceOverride: tax),
    ));
    await tester.pumpAndSettle();
  }

  group('QuoteFormScreen (F031)', () {
    testWidgets(
        'crear con 1 producto del inventario + 1 línea libre llama a '
        'createQuote con el payload correcto', (tester) async {
      final api = _FakeQuotesApi();
      await pump(tester, api);

      // 1) Elegir cliente.
      await tester.tap(find.byKey(const Key('quote_form_pick_customer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Constructora ACME'));
      await tester.pumpAndSettle();
      expect(find.text('Constructora ACME'), findsOneWidget);

      // 2) Agregar un producto del inventario.
      await tester.tap(find.byKey(const Key('quote_form_add_inventory')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cemento gris'));
      await tester.pumpAndSettle();

      // 3) Agregar una línea libre.
      await tester.tap(find.byKey(const Key('quote_form_add_free')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('free_line_name')), 'Mano de obra');
      await tester.enterText(
          find.byKey(const Key('free_line_qty')), '1');
      await tester.enterText(
          find.byKey(const Key('free_line_price')), '15000');
      await tester.tap(find.byKey(const Key('free_line_save')));
      await tester.pumpAndSettle();

      // 4) Guardar.
      await tester.tap(find.byKey(const Key('quote_form_save')));
      await tester.pumpAndSettle();

      expect(api.createCalls, 1);
      final payload = api.capturedCreatePayload!;
      expect(payload['customer_id'], 'c-acme');
      expect(payload['tax_rate'], 0);
      // Regresión: `valid_until` DEBE llevar zona horaria (UTC 'Z'). Un
      // DateTime local serializa sin 'Z' y el backend Go (RFC3339) lo
      // rechaza con 400 → "no se pudo guardar" (nunca se creó ninguna).
      final validUntil = payload['valid_until'] as String;
      expect(validUntil.endsWith('Z'), isTrue,
          reason: 'valid_until debe ir en UTC con sufijo Z (RFC3339)');
      expect(DateTime.tryParse(validUntil), isNotNull);

      final items = payload['items'] as List;
      expect(items.length, 2);
      // Producto del inventario → con product_id.
      final inventoryItem = items.firstWhere(
          (e) => (e as Map)['product_id'] == 'p-cemento') as Map;
      expect(inventoryItem['name'], 'Cemento gris');
      expect(inventoryItem['unit_price'], 25000);
      // Línea libre → sin product_id.
      final freeLine = items.firstWhere(
          (e) => !(e as Map).containsKey('product_id')) as Map;
      expect(freeLine['name'], 'Mano de obra');
      expect(freeLine['unit_price'], 15000);
    });

    testWidgets('guardar sin cliente muestra error y no llama a createQuote',
        (tester) async {
      final api = _FakeQuotesApi();
      await pump(tester, api);

      await tester.tap(find.byKey(const Key('quote_form_save')));
      await tester.pumpAndSettle();

      expect(api.createCalls, 0);
      expect(find.textContaining('Elija un cliente'), findsOneWidget);
    });

    testWidgets('los totales en vivo reflejan las líneas agregadas',
        (tester) async {
      final api = _FakeQuotesApi();
      await pump(tester, api);

      await tester.tap(find.byKey(const Key('quote_form_add_inventory')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cemento gris'));
      await tester.pumpAndSettle();

      // Subtotal = 1 x 25.000 = 25.000.
      expect(find.textContaining('25.000'), findsWidgets);
    });
  });
}
