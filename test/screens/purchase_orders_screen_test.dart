// Spec: specs/002-ordenes-compra/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/screens/purchases/purchase_orders_screen.dart';

/// Fake ApiService que controla la respuesta de los endpoints de órdenes
/// de compra sin red. Cubre los 3 estados obligatorios de UI_RULES §8
/// (loading / empty / error) y la lista del ciclo de vida.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  bool throwOnFetch = false;
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> suppliers = [];
  final List<String> received = [];
  final List<String> sent = [];

  @override
  Future<List<Map<String, dynamic>>> fetchPurchaseOrders({
    String? status,
  }) async {
    if (throwOnFetch) {
      throw const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión',
      );
    }
    if (status != null && status.isNotEmpty) {
      return orders.where((o) => o['status'] == status).toList();
    }
    return orders;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSuppliers() async => suppliers;

  @override
  Future<Map<String, dynamic>> receivePurchaseOrder(String uuid) async {
    received.add(uuid);
    orders = orders
        .map((o) => o['id'] == uuid ? {...o, 'status': 'recibida'} : o)
        .toList();
    return orders.firstWhere((o) => o['id'] == uuid);
  }

  @override
  Future<Map<String, dynamic>> sendPurchaseOrder(String uuid) async {
    sent.add(uuid);
    orders = orders
        .map((o) => o['id'] == uuid ? {...o, 'status': 'enviada'} : o)
        .toList();
    return {
      'status': 'enviada',
      'whatsapp_url': 'https://wa.me/573001112233?text=Pedido',
    };
  }
}

/// Construye una PO con la forma REAL del backend: el identificador
/// viaja en la llave `id` (no `uuid`) porque el modelo Go embebe
/// `BaseModel`.
Map<String, dynamic> _po({
  required String id,
  String supplierId = 'sup-1',
  String status = 'borrador',
  double total = 32000,
  List<Map<String, dynamic>>? items,
}) =>
    {
      'id': id,
      'tenant_id': 'tenant-1',
      'supplier_id': supplierId,
      'status': status,
      'total': total,
      'items': items ??
          [
            {
              'id': 'it-$id',
              'ingredient_id': 'ing-1',
              'name_snapshot': 'Arroz',
              'quantity': 10,
              'unit_cost': 3200,
            },
          ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('muestra un indicador de carga mientras pide las órdenes',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('estado vacío en español con CTA cuando no hay órdenes',
      (tester) async {
    final api = _FakeApi()..orders = [];
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tiene órdenes de compra'), findsOneWidget);
    expect(find.text('Nueva orden'), findsWidgets);
  });

  testWidgets('estado de error en español con botón Reintentar',
      (tester) async {
    final api = _FakeApi()..throwOnFetch = true;
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    // Nunca se filtra un stack trace (UI_RULES §8).
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('lista las órdenes con su estado y total (AC-01)',
      (tester) async {
    final api = _FakeApi()
      ..suppliers = [
        {'id': 'sup-1', 'company_name': 'Distribuidora El Sol'},
      ]
      ..orders = [
        _po(id: 'po-1', status: 'borrador'),
        _po(id: 'po-2', status: 'enviada'),
      ];
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Borrador'), findsOneWidget);
    expect(find.text('Enviada'), findsOneWidget);
    // El nombre del proveedor aparece en la tarjeta.
    expect(find.text('Distribuidora El Sol'), findsWidgets);
  });

  testWidgets('lista órdenes con la forma REAL del backend — id, no uuid '
      '(BUG-5)', (tester) async {
    // Regresión: el backend serializa el identificador como `id` (modelo
    // Go embebe BaseModel). Leer `uuid` da null y revienta.
    final api = _FakeApi()
      ..orders = [
        {
          'id': 'b1f2c3d4-0000-1111-2222-333344445555',
          'tenant_id': 'tenant-1',
          'supplier_id': 'sup-1',
          'status': 'borrador',
          'total': 10000.0,
          'items': const [],
        },
      ];
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    // Lista los datos de verdad — no cae al estado de error.
    expect(find.text('Borrador'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('el header no tiene más de 2 acciones laterales (UI_RULES §1)',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));
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
      ..suppliers = [
        {
          'id': 'sup-1',
          'company_name': 'Distribuidora Comercial Hermanos Gutierrez SAS',
        },
      ]
      ..orders = [_po(id: 'po-1', status: 'borrador')];
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrdersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
