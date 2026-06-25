// Spec: specs/002-ordenes-compra/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/models/purchase_order.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/screens/purchases/purchase_order_form_screen.dart';

/// Fake ApiService que controla proveedores, insumos y productos sin red,
/// y captura la PO creada/actualizada.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  bool throwOnLoad = false;
  List<Map<String, dynamic>> suppliers = [
    {'id': 'sup-1', 'company_name': 'Distribuidora El Sol'},
  ];
  List<Map<String, dynamic>> ingredients = [
    {'id': 'ing-1', 'name': 'Arroz', 'unit': 'kg', 'unit_cost': 3200},
  ];
  List<Map<String, dynamic>> products = [
    {'id': 'prod-1', 'name': 'Gaseosa', 'price': 1500},
  ];
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> updated = [];

  @override
  Future<List<Map<String, dynamic>>> fetchSuppliers() async {
    if (throwOnLoad) {
      throw const AppError(
          type: AppErrorType.network, message: 'Sin conexión');
    }
    return suppliers;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchIngredients() async {
    if (throwOnLoad) {
      throw const AppError(
          type: AppErrorType.network, message: 'Sin conexión');
    }
    return ingredients;
  }

  @override
  Future<Map<String, dynamic>> fetchProducts({
    int page = 1,
    int perPage = 20,
    String? branchId,
    bool sellableOnly = false,
  }) async {
    if (throwOnLoad) {
      throw const AppError(
          type: AppErrorType.network, message: 'Sin conexión');
    }
    return {'data': products};
  }

  @override
  Future<Map<String, dynamic>> createPurchaseOrder(
      Map<String, dynamic> data) async {
    created.add(data);
    return {...data, 'status': 'borrador'};
  }

  @override
  Future<Map<String, dynamic>> updatePurchaseOrder(
      String uuid, Map<String, dynamic> data) async {
    updated.add(data);
    return {...data, 'id': uuid, 'status': 'borrador'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('muestra carga mientras pide proveedores y productos',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrderFormScreen(api: api)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('estado de error con Reintentar si falla la carga',
      (tester) async {
    final api = _FakeApi()..throwOnLoad = true;
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrderFormScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('rechaza guardar sin proveedor', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrderFormScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_save_purchase_order')));
    await tester.pumpAndSettle();

    expect(api.created, isEmpty);
    expect(find.text('Debe escoger un proveedor para el pedido'),
        findsOneWidget);
  });

  testWidgets('rechaza guardar sin ítems aunque haya proveedor',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrderFormScreen(api: api)));
    await tester.pumpAndSettle();

    // Escoge el proveedor.
    await tester.tap(find.byKey(const Key('field_po_supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distribuidora El Sol').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_save_purchase_order')));
    await tester.pumpAndSettle();

    expect(api.created, isEmpty);
    expect(
        find.text('Agregue al menos un producto al pedido'), findsOneWidget);
  });

  testWidgets('crea una PO con proveedor y un ítem (AC-01)', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrderFormScreen(api: api)));
    await tester.pumpAndSettle();

    // Proveedor.
    await tester.tap(find.byKey(const Key('field_po_supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distribuidora El Sol').last);
    await tester.pumpAndSettle();

    // Agrega un ítem: abre el picker y escoge un insumo.
    await tester.tap(find.byKey(const Key('btn_add_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arroz'));
    await tester.pumpAndSettle();

    // Diálogo de cantidad/costo.
    await tester.enterText(
        find.byKey(const Key('field_item_quantity')), '10');
    await tester.enterText(find.byKey(const Key('field_item_cost')), '3200');
    await tester.tap(find.byKey(const Key('btn_confirm_item')));
    await tester.pumpAndSettle();

    // El total calculado aparece (10 × 3200 = 32.000).
    expect(find.text('\$ 32.000'), findsWidgets);

    await tester.tap(find.byKey(const Key('btn_save_purchase_order')));
    await tester.pumpAndSettle();

    expect(api.created, hasLength(1));
    expect(api.created.first['supplier_id'], 'sup-1');
    expect((api.created.first['items'] as List), hasLength(1));
    expect((api.created.first['items'] as List).first['ingredient_id'],
        'ing-1');
  });

  testWidgets('rechaza un ítem con cantidad cero (caso borde §9)',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
        MaterialApp(home: PurchaseOrderFormScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_add_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arroz'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field_item_quantity')), '0');
    await tester.enterText(find.byKey(const Key('field_item_cost')), '3200');
    await tester.tap(find.byKey(const Key('btn_confirm_item')));
    await tester.pumpAndSettle();

    expect(
      find.text('Cantidad y costo deben ser mayores que cero'),
      findsOneWidget,
    );
  });

  testWidgets('una PO enviada es de solo lectura (plan §4)', (tester) async {
    final api = _FakeApi();
    final sent = PurchaseOrder(
      uuid: 'po-1',
      supplierId: 'sup-1',
      status: 'enviada',
      items: [
        PurchaseOrderItem(
          nameSnapshot: 'Arroz',
          ingredientId: 'ing-1',
          quantity: 10,
          unitCost: 3200,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: PurchaseOrderFormScreen(api: api, existing: sent),
    ));
    await tester.pumpAndSettle();

    // No hay botón de guardar ni de agregar ítem en solo lectura.
    expect(find.byKey(const Key('btn_save_purchase_order')), findsNothing);
    expect(find.byKey(const Key('btn_add_item')), findsNothing);
    expect(find.text('Esta orden ya no se puede editar.'), findsOneWidget);
  });

  testWidgets('edita una PO borrador y la persiste vía PATCH',
      (tester) async {
    final api = _FakeApi();
    final draft = PurchaseOrder(
      uuid: 'po-9',
      supplierId: 'sup-1',
      status: 'borrador',
      items: [
        PurchaseOrderItem(
          nameSnapshot: 'Arroz',
          ingredientId: 'ing-1',
          quantity: 5,
          unitCost: 3200,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: PurchaseOrderFormScreen(api: api, existing: draft),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_save_purchase_order')));
    await tester.pumpAndSettle();

    expect(api.updated, hasLength(1));
    expect(api.updated.first['id'], 'po-9');
  });
}
