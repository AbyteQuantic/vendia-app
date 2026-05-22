// Spec: specs/031-cotizaciones/spec.md
//
// T-36 — Widget test de QuotesListScreen.
// Cobertura:
//   - la pantalla lista las cotizaciones devueltas por listQuotes.
//   - cada tarjeta muestra folio, cliente, estado y total.
//   - los FilterChips por estado filtran la lista.
//   - el buscador filtra por folio y por cliente.
//   - el FAB "Nueva" está presente.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/quotes/quotes_list_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — sirve cotizaciones fijas. Honra el filtro
/// `status` para que el test verifique el round-trip server-side.
class _FakeQuotesApi extends ApiService {
  _FakeQuotesApi(this._quotes) : super(AuthService());

  final List<Map<String, dynamic>> _quotes;
  String? lastStatusFilter;

  @override
  Future<Map<String, dynamic>> listQuotes({
    String? status,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    lastStatusFilter = status;
    final filtered = status == null
        ? _quotes
        : _quotes.where((q) => q['status'] == status).toList();
    return {
      'data': filtered,
      'meta': {'total': filtered.length, 'limit': limit, 'offset': offset},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  final fixtureQuotes = [
    {
      'id': 'q-1',
      'folio': 'COT-2026-0001',
      'status': 'borrador',
      'customer_id': 'c-acme',
      'customer_name': 'Constructora ACME',
      'total': 50000,
    },
    {
      'id': 'q-2',
      'folio': 'COT-2026-0002',
      'status': 'enviada',
      'customer_id': 'c-maria',
      'customer_name': 'María Pérez',
      'total': 120000,
    },
  ];

  Future<void> pump(WidgetTester tester, ApiService api) async {
    await tester.pumpWidget(MaterialApp(
      home: QuotesListScreen(apiOverride: api),
    ));
    await tester.pumpAndSettle();
  }

  group('QuotesListScreen (F031)', () {
    testWidgets('lista las cotizaciones devueltas por listQuotes',
        (tester) async {
      await pump(tester, _FakeQuotesApi(fixtureQuotes));

      expect(find.text('COT-2026-0001'), findsOneWidget);
      expect(find.text('COT-2026-0002'), findsOneWidget);
      expect(find.text('Constructora ACME'), findsOneWidget);
      expect(find.text('María Pérez'), findsOneWidget);
    });

    testWidgets('cada tarjeta muestra el estado y el total',
        (tester) async {
      await pump(tester, _FakeQuotesApi(fixtureQuotes));

      // "Borrador"/"Enviada" aparecen también en los FilterChips; el
      // badge de estado de la tarjeta es el que está dentro de la lista.
      final list = find.byKey(const Key('quotes_list'));
      expect(
          find.descendant(of: list, matching: find.text('Borrador')),
          findsOneWidget);
      expect(
          find.descendant(of: list, matching: find.text('Enviada')),
          findsOneWidget);
      expect(find.textContaining('50.000'), findsOneWidget);
      expect(find.textContaining('120.000'), findsOneWidget);
    });

    testWidgets('los FilterChips por estado filtran la lista',
        (tester) async {
      final api = _FakeQuotesApi(fixtureQuotes);
      await pump(tester, api);

      // Tocar el chip "Enviada" — solo queda la cotización enviada.
      await tester.tap(find.byKey(const Key('quotes_filter_enviada')));
      await tester.pumpAndSettle();

      expect(api.lastStatusFilter, 'enviada');
      expect(find.text('COT-2026-0002'), findsOneWidget);
      expect(find.text('COT-2026-0001'), findsNothing);
    });

    testWidgets('el buscador filtra por cliente', (tester) async {
      await pump(tester, _FakeQuotesApi(fixtureQuotes));

      await tester.enterText(
          find.byKey(const Key('quotes_search')), 'maría');
      await tester.pumpAndSettle();

      expect(find.text('COT-2026-0002'), findsOneWidget);
      expect(find.text('COT-2026-0001'), findsNothing);
    });

    testWidgets('el buscador filtra por folio', (tester) async {
      await pump(tester, _FakeQuotesApi(fixtureQuotes));

      await tester.enterText(
          find.byKey(const Key('quotes_search')), 'COT-2026-0001');
      await tester.pumpAndSettle();

      // El texto del folio también aparece en el campo de búsqueda;
      // verificamos contra las tarjetas de la lista.
      final list = find.byKey(const Key('quotes_list'));
      expect(
          find.descendant(of: list, matching: find.text('COT-2026-0001')),
          findsOneWidget);
      expect(
          find.descendant(of: list, matching: find.text('COT-2026-0002')),
          findsNothing);
    });

    testWidgets('el FAB "Nueva" está presente', (tester) async {
      await pump(tester, _FakeQuotesApi(fixtureQuotes));

      expect(find.byKey(const Key('quotes_new_fab')), findsOneWidget);
    });

    testWidgets('lista vacía muestra estado vacío', (tester) async {
      await pump(tester, _FakeQuotesApi(const []));

      expect(find.textContaining('Aún no tiene cotizaciones'),
          findsOneWidget);
    });
  });
}
