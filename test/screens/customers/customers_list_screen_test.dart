// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// T-28 — Widget test de CustomersListScreen.
// Cobertura:
//   - la pantalla lista los clientes devueltos por listCustomers.
//   - cada tarjeta muestra los agregados (total gastado, # compras).
//   - el buscador filtra por nombre y por teléfono.
//   - el AppBar tiene el botón "Importar desde Excel/CSV" (T-32b).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/customers/customers_list_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble mínima de ApiService — solo [listCustomers].
class _FakeCustomersApi extends ApiService {
  _FakeCustomersApi(this._customers) : super(AuthService());

  final List<Map<String, dynamic>> _customers;

  @override
  Future<Map<String, dynamic>> listCustomers({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    return {
      'data': _customers,
      'meta': {'total': _customers.length, 'limit': limit, 'offset': offset},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  final fixtureCustomers = [
    {
      'id': 'c-maria',
      'name': 'María Pérez',
      'phone': '3001112233',
      'total_spent': 20000,
      'purchase_count': 2,
      'last_purchase_at': '2026-05-20T10:00:00Z',
    },
    {
      'id': 'c-juan',
      'name': 'Juan García',
      'phone': '3109998877',
      'total_spent': 25000,
      'purchase_count': 1,
      'last_purchase_at': '2026-05-19T15:00:00Z',
    },
  ];

  Future<void> pump(WidgetTester tester, ApiService api) async {
    await tester.pumpWidget(MaterialApp(
      home: CustomersListScreen(apiOverride: api),
    ));
    await tester.pumpAndSettle();
  }

  group('CustomersListScreen (F030)', () {
    testWidgets('lista los clientes devueltos por listCustomers',
        (tester) async {
      await pump(tester, _FakeCustomersApi(fixtureCustomers));

      expect(find.text('María Pérez'), findsOneWidget);
      expect(find.text('Juan García'), findsOneWidget);
    });

    testWidgets('cada tarjeta muestra los agregados de compra',
        (tester) async {
      await pump(tester, _FakeCustomersApi(fixtureCustomers));

      // total gastado formateado en COP
      expect(find.textContaining('20.000'), findsOneWidget);
      expect(find.textContaining('25.000'), findsOneWidget);
      // número de compras
      expect(find.textContaining('2 compras'), findsOneWidget);
      expect(find.textContaining('1 compra'), findsOneWidget);
    });

    testWidgets('el buscador filtra por nombre', (tester) async {
      await pump(tester, _FakeCustomersApi(fixtureCustomers));

      await tester.enterText(
          find.byKey(const Key('customers_search')), 'juan');
      await tester.pumpAndSettle();

      expect(find.text('Juan García'), findsOneWidget);
      expect(find.text('María Pérez'), findsNothing);
    });

    testWidgets('el buscador filtra por teléfono', (tester) async {
      await pump(tester, _FakeCustomersApi(fixtureCustomers));

      await tester.enterText(
          find.byKey(const Key('customers_search')), '3109998877');
      await tester.pumpAndSettle();

      expect(find.text('Juan García'), findsOneWidget);
      expect(find.text('María Pérez'), findsNothing);
    });

    testWidgets('el AppBar tiene el botón de importar desde Excel/CSV',
        (tester) async {
      await pump(tester, _FakeCustomersApi(fixtureCustomers));

      expect(
          find.byKey(const Key('customers_import_button')), findsOneWidget);
    });

    testWidgets('lista vacía muestra estado vacío', (tester) async {
      await pump(tester, _FakeCustomersApi(const []));

      expect(find.textContaining('Aún no tiene clientes'), findsOneWidget);
    });
  });
}
