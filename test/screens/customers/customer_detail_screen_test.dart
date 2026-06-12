// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// T-30 — Widget test de CustomerDetailScreen.
// Cobertura:
//   - el header muestra nombre + teléfono del cliente.
//   - las summary cards muestran total gastado, # compras y
//     primera/última visita.
//   - la timeline lista las ventas del historial.
//   - un cliente sin compras muestra el summary en cero y la lista
//     vacía (AC-06 — cliente recién creado).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/customers/customer_detail_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble mínima de ApiService — solo [getCustomerHistory].
class _FakeHistoryApi extends ApiService {
  _FakeHistoryApi(this._history) : super(AuthService());

  final Map<String, dynamic> _history;

  @override
  Future<Map<String, dynamic>> getCustomerHistory(String id) async {
    return _history;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  final mariaHistory = {
    'customer': {
      'id': 'c-maria',
      'name': 'María Pérez',
      'phone': '3001112233',
    },
    'summary': {
      'total_spent': 20000,
      'purchase_count': 2,
      'first_purchase_at': '2026-05-18T09:00:00Z',
      'last_purchase_at': '2026-05-20T10:00:00Z',
    },
    'sales': [
      {
        'id': 's-1',
        'total': 12000,
        'created_at': '2026-05-20T10:00:00Z',
        'items_count': 3,
        'payment_method': 'cash',
      },
      {
        'id': 's-2',
        'total': 8000,
        'created_at': '2026-05-18T09:00:00Z',
        'items_count': 1,
        'payment_method': 'cash',
      },
    ],
  };

  // Venta con array `items` (como lo devuelve el backend con Preload).
  final orianaHistory = {
    'customer': {
      'id': 'c-oriana',
      'name': 'Oriana',
      'phone': '3009998877',
    },
    'summary': {
      'total_spent': 12000,
      'purchase_count': 1,
    },
    'sales': [
      {
        'id': 's-ori',
        'total': 12000,
        'created_at': '2026-05-29T15:48:00Z',
        'payment_method': 'credit',
        'items': [
          {
            'name': 'Empanada De Pollo',
            'price': 2500,
            'quantity': 2,
            'subtotal': 5000,
          },
          {
            'name': 'Coca Cola',
            'price': 7000,
            'quantity': 1,
            'subtotal': 7000,
          },
        ],
      },
    ],
  };

  final carlosNoPurchases = {
    'customer': {
      'id': 'c-carlos',
      'name': 'Carlos López',
      'phone': '',
    },
    'summary': {
      'total_spent': 0,
      'purchase_count': 0,
    },
    'sales': [],
  };

  Future<void> pump(
    WidgetTester tester,
    ApiService api, {
    String name = 'María Pérez',
    String id = 'c-maria',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: CustomerDetailScreen(
        customerId: id,
        customerName: name,
        apiOverride: api,
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('CustomerDetailScreen (F030)', () {
    testWidgets('el header muestra nombre y teléfono', (tester) async {
      await pump(tester, _FakeHistoryApi(mariaHistory));

      expect(find.text('María Pérez'), findsWidgets);
      expect(find.text('3001112233'), findsOneWidget);
    });

    testWidgets('las summary cards muestran gastado y # de compras',
        (tester) async {
      await pump(tester, _FakeHistoryApi(mariaHistory));

      expect(find.textContaining('20.000'), findsWidgets);
      // El conteo de compras aparece en la summary card.
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('la timeline lista las ventas del historial',
        (tester) async {
      await pump(tester, _FakeHistoryApi(mariaHistory));

      expect(find.byKey(const Key('customer_sales_timeline')),
          findsOneWidget);
      expect(find.textContaining('12.000'), findsWidgets);
      expect(find.textContaining('8.000'), findsWidgets);
    });

    testWidgets(
        'abrir una venta del historial muestra sus PRODUCTOS (no "Sin items")',
        (tester) async {
      await pump(tester, _FakeHistoryApi(orianaHistory),
          name: 'Oriana', id: 'c-oriana');

      // Tocar el tile de la venta DENTRO de la timeline (no la summary card).
      final tile = find.descendant(
        of: find.byKey(const Key('customer_sales_timeline')),
        matching: find.byType(InkWell),
      );
      await tester.tap(tile.first);
      await tester.pumpAndSettle();

      // El detalle muestra los productos comprados, NO "Sin items registrados".
      expect(find.text('Empanada De Pollo'), findsOneWidget);
      expect(find.textContaining('Sin items registrados'), findsNothing);
    });

    testWidgets('cliente sin compras: summary en cero y lista vacía',
        (tester) async {
      await pump(
        tester,
        _FakeHistoryApi(carlosNoPurchases),
        name: 'Carlos López',
        id: 'c-carlos',
      );

      expect(find.text('Carlos López'), findsWidgets);
      // Mensaje de "sin compras aún".
      expect(find.textContaining('sin compras'), findsOneWidget);
    });
  });
}
