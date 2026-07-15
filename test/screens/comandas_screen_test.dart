// Spec: specs/105-hito-restaurante-comandas/spec.md — F2 (KDS Flutter).
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/order_ticket.dart';
import 'package:vendia_pos/screens/kds/comandas_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Fake que solo implementa lo que el KDS usa. Cualquier otra llamada
/// revienta con UnimplementedError (tripwire deliberado).
class _FakeApi extends ApiService {
  _FakeApi({required this.rows}) : super(AuthService());

  List<Map<String, dynamic>> rows;
  bool failFetch = false;
  final List<(String, String)> statusCalls = [];

  @override
  Future<List<Map<String, dynamic>>> fetchOrders({String? status}) async {
    if (failFetch) throw Exception('sin red');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<Map<String, dynamic>> updateOrderStatus(String uuid, String status,
      {String? paymentMethod}) async {
    statusCalls.add((uuid, status));
    return {'id': uuid, 'status': status};
  }
}

Map<String, dynamic> _row({
  required String id,
  required String label,
  String status = 'nuevo',
  bool paid = false,
  String? listoAt,
  List<Map<String, dynamic>>? items,
}) {
  return {
    'id': id,
    'label': label,
    'status': status,
    'type': 'mesa',
    'total': 15000,
    'created_at':
        DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
    if (paid) 'paid_at': DateTime.now().toIso8601String(),
    if (listoAt != null) 'listo_at': listoAt,
    'items': items ??
        [
          {
            'product_uuid': 'p1',
            'product_name': 'Empanada',
            'quantity': 3,
            'unit_price': 5000,
            'notes': 'sin cebolla',
            'duration_min': 20,
          },
        ],
  };
}

Widget _app(_FakeApi api) => MaterialApp(
      home: ComandasScreen(
        apiOverride: api,
        // Poll largo: los tests controlan el tiempo con pump().
        pollInterval: const Duration(minutes: 30),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('OrderTicket.fromApi (Spec 105)', () {
    test('parsea id→uuid, entregado, notas y duration; MAX de ítems', () {
      final t = OrderTicket.fromApi({
        'id': 'abc-123',
        'label': 'Mesa 4',
        'status': 'entregado',
        'type': 'mesa',
        'total': 10000,
        'created_at': '2026-07-15T10:00:00Z',
        'listo_at': '2026-07-15T10:20:00Z',
        'paid_at': '2026-07-15T09:55:00Z',
        'items': [
          {
            'product_uuid': 'p1',
            'product_name': 'Bandeja',
            'quantity': 1,
            'unit_price': 10000,
            'notes': 'sin arroz',
            'duration_min': 25,
          },
          {
            'product_uuid': 'p2',
            'product_name': 'Jugo',
            'quantity': 2,
            'unit_price': 3000,
            'duration_min': 5,
          },
        ],
      });
      expect(t.uuid, 'abc-123');
      expect(t.status, OrderStatus.entregado);
      expect(t.isPrepaid, isTrue);
      expect(t.listoAt, isNotNull);
      expect(t.maxDurationMin, 25);
      expect(t.items.first.notes, 'sin arroz');
    });

    test('duration_min 0 se trata como sin tiempo (null)', () {
      final t = OrderTicket.fromApi(_row(id: 'x', label: 'M1', items: [
        {
          'product_uuid': 'p1',
          'product_name': 'Café',
          'quantity': 1,
          'unit_price': 2000,
          'duration_min': 0,
        },
      ]));
      expect(t.maxDurationMin, isNull);
    });
  });

  group('ComandasScreen — pestaña Cocina', () {
    testWidgets('pinta tickets FIFO con notas, all-day y franja Listos',
        (tester) async {
      final api = _FakeApi(rows: [
        _row(id: 'o1', label: 'Mesa 1', status: 'nuevo'),
        _row(id: 'o2', label: 'Mesa 2', status: 'preparando'),
        _row(id: 'o3', label: 'Mesa 3', status: 'listo',
            listoAt: DateTime.now().toIso8601String()),
      ]);
      await tester.pumpWidget(_app(api));
      await tester.pump(); // resuelve el fetch

      expect(find.text('Cocina (2)'), findsOneWidget);
      expect(find.text('Para entregar (1)'), findsOneWidget);
      expect(find.text('Mesa 1'), findsOneWidget);
      expect(find.text('Mesa 2'), findsOneWidget);
      expect(find.text('“sin cebolla”'), findsNWidgets(2));
      expect(find.text('Empezar a preparar'), findsOneWidget);
      expect(find.text('Pedido listo 🛎️'), findsOneWidget);
      // All-day: 3 empanadas por ticket en cocina → 6×.
      expect(find.text('6× Empanada'), findsOneWidget);
      // Franja Listos con Mesa 3.
      expect(find.text('LISTOS ESPERANDO ENTREGA (1)'), findsOneWidget);
      expect(find.textContaining('Mesa 3'), findsOneWidget);
    });

    testWidgets('DESHACER dentro de 3 s revierte sin llamar la API',
        (tester) async {
      final api = _FakeApi(rows: [
        _row(id: 'o1', label: 'Mesa 1', status: 'preparando'),
      ]);
      await tester.pumpWidget(_app(api));
      await tester.pump();

      await tester.tap(find.text('Pedido listo 🛎️'));
      await tester.pump();
      // El ticket saltó a la franja de listos (optimista).
      expect(find.text('Pedido listo 🛎️'), findsNothing);

      // Deja entrar la animación del SnackBar antes de tocar DESHACER
      // (sin agotar la ventana de 3 s).
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('DESHACER'));
      await tester.pump();
      expect(find.text('Pedido listo 🛎️'), findsOneWidget);

      // Pasan los 3 s: no debe haberse enviado NADA (se deshizo).
      await tester.pump(const Duration(seconds: 4));
      expect(api.statusCalls, isEmpty);
    });

    testWidgets('sin deshacer, a los 3 s envía el PATCH', (tester) async {
      final api = _FakeApi(rows: [
        _row(id: 'o1', label: 'Mesa 1', status: 'nuevo'),
      ]);
      await tester.pumpWidget(_app(api));
      await tester.pump();

      await tester.tap(find.text('Empezar a preparar'));
      await tester.pump(const Duration(seconds: 4));

      expect(api.statusCalls, [('o1', 'preparando')]);
    });
  });

  group('ComandasScreen — pestaña Para entregar', () {
    testWidgets('ENTREGADO llama la API y saca el ticket', (tester) async {
      final api = _FakeApi(rows: [
        _row(id: 'o3', label: 'Mesa 3', status: 'listo',
            listoAt: DateTime.now().toIso8601String()),
      ]);
      await tester.pumpWidget(_app(api));
      await tester.pump();

      await tester.tap(find.text('Para entregar (1)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Por cobrar'), findsOneWidget);
      await tester.tap(find.text('Confirmar ENTREGA'));
      await tester.pumpAndSettle();

      expect(api.statusCalls, [('o3', 'entregado')]);
      expect(find.text('Nada por entregar'), findsOneWidget);
    });

    testWidgets('ticket prepago muestra PAGADO, no "Por cobrar"',
        (tester) async {
      final api = _FakeApi(rows: [
        _row(id: 'o9', label: 'Pedido 9', status: 'listo', paid: true,
            listoAt: DateTime.now().toIso8601String()),
      ]);
      await tester.pumpWidget(_app(api));
      await tester.pump();

      await tester.tap(find.text('Para entregar (1)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PAGADO'), findsOneWidget);
      expect(find.textContaining('Por cobrar'), findsNothing);
    });
  });

  group('ComandasScreen — estados', () {
    testWidgets('vacío: mensaje amable en español', (tester) async {
      final api = _FakeApi(rows: []);
      await tester.pumpWidget(_app(api));
      await tester.pump();
      expect(find.text('No hay pedidos en cocina'), findsOneWidget);
    });

    testWidgets('primera carga fallida: botón Reintentar recupera',
        (tester) async {
      final api = _FakeApi(rows: [_row(id: 'o1', label: 'Mesa 1')])
        ..failFetch = true;
      await tester.pumpWidget(_app(api));
      await tester.pump();

      expect(find.text('Reintentar'), findsOneWidget);

      api.failFetch = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Mesa 1'), findsOneWidget);
    });
  });
}
