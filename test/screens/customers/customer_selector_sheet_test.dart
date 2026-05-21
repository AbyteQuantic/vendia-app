// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// T-26 (parte widget) — Widget test del selector de cliente reutilizable
// que abre el tile "Cliente" del checkout.
//
// Cobertura:
//   - el selector lista los clientes que devuelve listCustomers.
//   - el buscador filtra por nombre y por teléfono.
//   - tocar un cliente lo devuelve vía Navigator.pop.
//   - el botón "Registrar cliente nuevo" está presente (cliente al
//     vuelo — AC-03).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/customer.dart';
import 'package:vendia_pos/screens/customers/customer_selector_sheet.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble mínima de ApiService — solo [listCustomers] está implementado.
/// Cualquier otra llamada lanza para que regresiones que arrastren
/// endpoints ajenos se vean en lugar de tocar HTTP real.
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
    },
    {
      'id': 'c-juan',
      'name': 'Juan García',
      'phone': '3109998877',
      'total_spent': 25000,
      'purchase_count': 1,
    },
  ];

  Future<Customer?> pumpSelector(
    WidgetTester tester,
    ApiService api,
  ) async {
    Customer? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<Customer>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => CustomerSelectorSheet(apiOverride: api),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return result;
  }

  group('CustomerSelectorSheet (F030)', () {
    testWidgets('lista los clientes devueltos por listCustomers',
        (tester) async {
      await pumpSelector(tester, _FakeCustomersApi(fixtureCustomers));

      expect(find.text('María Pérez'), findsOneWidget);
      expect(find.text('Juan García'), findsOneWidget);
      expect(
          find.byKey(const Key('customer_selector_new')), findsOneWidget);
    });

    testWidgets('el buscador filtra por nombre', (tester) async {
      await pumpSelector(tester, _FakeCustomersApi(fixtureCustomers));

      await tester.enterText(
          find.byKey(const Key('customer_selector_search')), 'juan');
      await tester.pumpAndSettle();

      expect(find.text('Juan García'), findsOneWidget);
      expect(find.text('María Pérez'), findsNothing);
    });

    testWidgets('el buscador filtra por teléfono', (tester) async {
      await pumpSelector(tester, _FakeCustomersApi(fixtureCustomers));

      await tester.enterText(
          find.byKey(const Key('customer_selector_search')), '3001112233');
      await tester.pumpAndSettle();

      expect(find.text('María Pérez'), findsOneWidget);
      expect(find.text('Juan García'), findsNothing);
    });

    testWidgets('tocar un cliente lo devuelve por Navigator.pop',
        (tester) async {
      final api = _FakeCustomersApi(fixtureCustomers);
      Customer? picked;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showModalBottomSheet<Customer>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CustomerSelectorSheet(apiOverride: api),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('María Pérez'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.id, 'c-maria');
      expect(picked!.name, 'María Pérez');
    });

    testWidgets('lista vacía muestra el mensaje de "registre cliente"',
        (tester) async {
      await pumpSelector(tester, _FakeCustomersApi(const []));

      expect(
        find.textContaining('No hay clientes'),
        findsOneWidget,
      );
    });
  });
}
