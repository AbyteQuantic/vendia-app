// Spec: specs/003-trabajos-muebles/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/screens/work_orders/work_orders_screen.dart';

/// Fake ApiService que controla la respuesta de los endpoints de trabajos
/// sin red. Cubre los 3 estados obligatorios de UI_RULES §8
/// (loading / empty / error) y la lista del ciclo de vida.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  bool throwOnFetch = false;
  List<Map<String, dynamic>> workOrders = [];
  List<Map<String, dynamic>> customers = [];

  @override
  Future<List<Map<String, dynamic>>> fetchWorkOrders({
    String? status,
    String? type,
  }) async {
    if (throwOnFetch) {
      throw const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión',
      );
    }
    return workOrders;
  }

  @override
  Future<Map<String, dynamic>> fetchCustomers({
    int page = 1,
    int perPage = 20,
  }) async =>
      {'data': customers};
}

/// Construye un trabajo con la forma REAL del backend: el identificador
/// viaja en la llave `id` (no `uuid`) porque el modelo Go embebe
/// `BaseModel`.
Map<String, dynamic> _wo({
  required String id,
  String customerId = 'cust-1',
  String type = 'fabricacion',
  String status = 'cotizacion',
  double total = 90000,
}) =>
    {
      'id': id,
      'tenant_id': 'tenant-1',
      'customer_id': customerId,
      'type': type,
      'status': status,
      'description': 'Mesa de comedor a la medida',
      'total': total,
      'abonado': 0.0,
      'saldo': total,
      'items': [
        {
          'id': 'it-$id',
          'kind': 'mano_obra',
          'description': 'Armado',
          'quantity': 1,
          'unit_price': total,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('muestra un indicador de carga mientras pide los trabajos',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('estado vacío en español con CTA cuando no hay trabajos',
      (tester) async {
    final api = _FakeApi()..workOrders = [];
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tiene trabajos'), findsOneWidget);
    expect(find.text('Nuevo trabajo'), findsWidgets);
  });

  testWidgets('estado de error en español con botón Reintentar',
      (tester) async {
    final api = _FakeApi()..throwOnFetch = true;
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    // Nunca se filtra un stack trace (UI_RULES §8).
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('lista los trabajos con su estado, tipo y total (AC-01)',
      (tester) async {
    final api = _FakeApi()
      ..customers = [
        {'id': 'cust-1', 'name': 'Doña Marta'},
      ]
      ..workOrders = [
        _wo(id: 'wo-1', status: 'cotizacion', type: 'fabricacion'),
        _wo(id: 'wo-2', status: 'en_proceso', type: 'reparacion'),
      ];
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Cotización'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    // El nombre del cliente aparece en la tarjeta.
    expect(find.text('Doña Marta'), findsWidgets);
  });

  testWidgets('lista trabajos con la forma REAL del backend — id, no uuid '
      '(BUG-5)', (tester) async {
    // Regresión: el backend serializa el identificador como `id` (modelo
    // Go embebe BaseModel). Leer `uuid` da null y revienta.
    final api = _FakeApi()
      ..workOrders = [
        {
          'id': 'b1f2c3d4-0000-1111-2222-333344445555',
          'tenant_id': 'tenant-1',
          'customer_id': 'cust-1',
          'type': 'fabricacion',
          'status': 'cotizacion',
          'description': 'Closet',
          'total': 10000.0,
          'items': const [],
        },
      ];
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    // Lista los datos de verdad — no cae al estado de error.
    expect(find.text('Cotización'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('el header no tiene más de 2 acciones laterales (UI_RULES §1)',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect((appBar.actions ?? const []).length, lessThanOrEqualTo(2));
  });

  testWidgets('renderiza sin overflow en una pantalla de 360dp',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi()
      ..customers = [
        {
          'id': 'cust-1',
          'name': 'Distribuidora Comercial Hermanos Gutierrez SAS',
        },
      ]
      ..workOrders = [_wo(id: 'wo-1', status: 'cotizacion')];
    await tester.pumpWidget(MaterialApp(home: WorkOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
