import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

typedef MockApiHandler = dynamic Function(Map<String, dynamic> args);

class MockApiService extends ApiService {
  MockApiService() : super(AuthService()) {
    _setDefaults();
  }

  final Map<String, MockApiHandler> _handlers = {};
  int _callCount = 0;
  final List<String> _callLog = [];

  List<String> get callLog => List.unmodifiable(_callLog);
  int get callCount => _callCount;

  void reset() {
    _handlers.clear();
    _callCount = 0;
    _callLog.clear();
    _setDefaults();
  }

  void _log(String method) {
    _callCount++;
    _callLog.add(method);
  }

  dynamic _handle(String key, [Map<String, dynamic> args = const {}]) {
    final handler = _handlers[key];
    if (handler != null) return handler(args);
    throw UnimplementedError(
      'MockApiService.$key not configured. '
      'Call mock$key(handler) in your test setup.',
    );
  }

  void _setDefaults() {
    _handlers['login'] = (_) => {
          'access_token': 'mock-access-token',
          'refresh_token': 'mock-refresh-token',
          'tenant': {'uuid': 'tenant-1', 'name': 'Test Tienda'},
          'employee': {'uuid': 'emp-1', 'name': 'Test Cashier'},
        };
    _handlers['selectWorkspace'] = (_) => {
          'access_token': 'mock-ws-access-token',
          'refresh_token': 'mock-ws-refresh-token',
          'tenant': {'uuid': 'tenant-1', 'name': 'Test Tienda'},
          'branches': [
            {'id': 'branch-1', 'name': 'Sede Principal'},
            {'id': 'branch-2', 'name': 'Sede Secundaria'},
          ],
        };
    _handlers['fetchBranches'] = (_) => [
          {'id': 'branch-1', 'name': 'Sede Principal', 'is_active': true},
          {'id': 'branch-2', 'name': 'Sede Secundaria', 'is_active': true},
        ];
    _handlers['fetchProducts'] = (_) => {
          'products': [
            {
              'id': 'prod-1',
              'name': 'Arroz Diana 1kg',
              'barcode': '7701001001001',
              'price': 3200,
              'stock': 50,
              'category': 'Granos',
            },
            {
              'id': 'prod-2',
              'name': 'Aceite Gourmet 900ml',
              'barcode': '7702002002002',
              'price': 12400,
              'stock': 30,
              'category': 'Aceites',
            },
            {
              'id': 'prod-3',
              'name': 'Pan Bimbo 500g',
              'barcode': '7703003003003',
              'price': 6800,
              'stock': 20,
              'category': 'Panadería',
            },
            {
              'id': 'prod-4',
              'name': 'Leche Colanta 1L',
              'barcode': '7704004004004',
              'price': 4500,
              'stock': 0,
              'category': 'Lácteos',
            },
          ],
          'total': 4,
          'page': 1,
        };
    _handlers['lookupProductByBarcode'] = (args) => {
          'id': 'prod-1',
          'name': 'Arroz Diana 1kg',
          'barcode': args['code'],
          'price': 3200,
          'stock': 50,
          'category': 'Granos',
        };
    _handlers['createSale'] = (args) => {
          'uuid': 'sale-${DateTime.now().millisecondsSinceEpoch}',
          'total': args['total'],
          'cash_amount': args['cash_amount'],
          'change_due': (args['cash_amount'] ?? 0) - (args['total'] ?? 0),
          'payment_method': args['payment_method'] ?? 'cash',
          'status': 'completed',
          'created_at': DateTime.now().toIso8601String(),
        };
    _handlers['fetchSales'] = (_) => {
          'sales': [],
          'total': 0,
          'page': 1,
        };
    _handlers['fetchSalesToday'] = (_) => {
          'total_sales': 0,
          'total_revenue': 0,
          'sales': [],
        };
    _handlers['uploadReceipt'] = (_) =>
        'https://mock-storage.vendia.store/receipts/mock-receipt.jpg';
    _handlers['fetchCustomers'] = (_) => {
          'customers': [
            {
              'uuid': 'cust-1',
              'name': 'Juan Pérez',
              'phone': '3001112233',
              'total_debt': 15000,
            },
            {
              'uuid': 'cust-2',
              'name': 'María López',
              'phone': '3004445566',
              'total_debt': 0,
            },
          ],
          'total': 2,
        };
    _handlers['fetchCredits'] = (_) => {
          'credits': [
            {
              'uuid': 'credit-1',
              'customer_uuid': 'cust-1',
              'customer_name': 'Juan Pérez',
              'total': 50000,
              'paid': 35000,
              'balance': 15000,
              'status': 'active',
            },
          ],
          'total': 1,
        };
    _handlers['fetchCreditsGroupedByCustomer'] = (_) => [
          {
            'customer_uuid': 'cust-1',
            'customer_name': 'Juan Pérez',
            'phone': '3001112233',
            'total_balance': 15000,
            'credits': [
              {
                'uuid': 'credit-1',
                'total': 50000,
                'paid': 35000,
                'balance': 15000,
                'status': 'active',
              },
            ],
          },
        ];
    _handlers['recordCreditPayment'] = (args) => {
          'uuid': 'payment-${DateTime.now().millisecondsSinceEpoch}',
          'credit_uuid': args['credit_uuid'],
          'amount': args['amount'],
          'status': 'completed',
        };
    _handlers['fetchTableTabByLabel'] = (_) => null;
    _handlers['upsertTableTab'] = (args) => {
          'uuid': 'tab-${DateTime.now().millisecondsSinceEpoch}',
          'label': args['label'],
          'items': args['items'],
          'total': 0,
          'status': 'open',
          'session_token': 'mock-session-token',
        };
    _handlers['addItemsToTableTab'] = (args) => {
          'uuid': 'tab-${DateTime.now().millisecondsSinceEpoch}',
          'label': args['label'],
          'items': args['items'],
          'total': 0,
          'status': 'open',
        };
    _handlers['closeOrder'] = (args) => {
          'uuid': args['uuid'] ?? 'tab-close-uuid',
          'status': 'closed',
          'total': args['total'] ?? 0,
        };
    _handlers['createProduct'] = (args) => {
          'id': 'prod-new-${DateTime.now().millisecondsSinceEpoch}',
          'name': args['name'],
          'price': args['price'],
          'stock': args['stock'] ?? 0,
          'barcode': args['barcode'] ?? '',
        };
    _handlers['scanInvoice'] = (_) => {
          'products': [
            {'name': 'Producto Factura 1', 'price': 5000, 'quantity': 2},
            {'name': 'Producto Factura 2', 'price': 3000, 'quantity': 1},
          ],
          'total': 13000,
        };
    _handlers['updateProduct'] = (args) => {
          'id': args['id'],
          'name': args['name'],
          'price': args['price'],
          'stock': args['stock'] ?? 0,
        };
    _handlers['restockProduct'] = (args) => {
          'id': args['id'],
          'quantity': args['quantity'],
          'cost': args['cost'],
          'new_stock': 80,
        };
    _handlers['deleteProduct'] = (_) => {};
    _handlers['lookupBarcode'] = (args) => {
          'id': 'prod-1',
          'name': 'Arroz Diana 1kg',
          'barcode': args['barcode'],
          'price': 3200,
          'stock': 50,
        };
    _handlers['verifyPin'] = (_) => {
          'valid': true,
          'employee': {
            'uuid': 'emp-1',
            'name': 'Test Cashier',
            'role': 'admin',
          },
        };
    _handlers['logout'] = (_) => {};
    _handlers['fetchStoreConfig'] = (_) => {
          'store_name': 'Test Tienda',
          'currency': 'COP',
          'is_open': true,
          'payment_methods': [
            {'key': 'cash', 'name': 'Efectivo'},
            {'key': 'transfer', 'name': 'Transferencia'},
            {'key': 'nequi', 'name': 'Nequi'},
            {'key': 'daviplata', 'name': 'Daviplata'},
          ],
        };
    _handlers['fetchAnalyticsDashboard'] = (_) => {
          'total_sales_today': 0,
          'total_revenue_today': 0,
          'total_products': 100,
          'low_stock_count': 5,
          'total_customers': 25,
        };
    _handlers['fetchOpenAccounts'] = (_) => <Map<String, dynamic>>[];
    _handlers['appendToFiado'] = (args) => {
          'uuid': args['credit_id'] ?? 'credit-default',
          'total_amount': args['total_amount'],
          'new_balance': (args['total_amount'] as int?) ?? 0,
          'status': 'active',
        };
    _handlers['closeFiado'] = (args) => {
          'uuid': args['credit_id'] ?? 'credit-default',
          'status': 'closed',
          'reason': args['reason'] ?? '',
        };
    _handlers['removeItemFromTab'] = (args) => {
          'status': 'ok',
          'order_uuid': args['order_uuid'],
          'item_id': args['item_id'],
        };
    _handlers['fetchPublicTableSession'] = (args) => {
          'uuid': 'tab-live-001',
          'label': 'Mesa 5',
          'items': [
            {
              'product_uuid': 'prod-1',
              'product_name': 'Arroz Diana 1kg',
              'quantity': 2,
              'unit_price': 3200,
            },
          ],
          'total': 6400,
          'status': 'open',
        };
    _handlers['registerPartialPayment'] = (args) => {
          'payment_id': 'payment-${DateTime.now().millisecondsSinceEpoch}',
          'order_id': args['order_id'],
          'amount': args['amount'],
          'payment_method': args['payment_method'],
          'status': 'approved',
          'remaining_balance': 0,
        };
    _handlers['confirmPartialPayment'] = (args) => {
          'payment_id': args['payment_id'],
          'status': 'confirmed',
          'already': false,
        };
    _handlers['lookupBarcode'] = (args) => {
          'id': 'prod-1',
          'name': 'Arroz Diana 1kg',
          'barcode': args['barcode'],
          'price': 3200,
          'stock': 50,
        };
    _handlers['voiceInventory'] = (args) => [
          {
            'name': 'Producto Voz 1',
            'quantity': 5,
            'unit_price': 8000,
            'presentation': 'Bolsa',
            'content': '500g',
          },
        ];
  }

  void mock(String method, MockApiHandler handler) {
    _handlers[method] = handler;
  }

  @override
  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    _log('login');
    return _handle('login', {'phone': phone, 'password': password});
  }

  @override
  Future<Map<String, dynamic>> selectWorkspace({
    required String workspaceId,
    required String tempToken,
    required String password,
  }) async {
    _log('selectWorkspace');
    return _handle('selectWorkspace', {
      'workspace_id': workspaceId,
      'temp_token': tempToken,
      'password': password,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBranches() async {
    _log('fetchBranches');
    return List<Map<String, dynamic>>.from(_handle('fetchBranches'));
  }

  @override
  Future<Map<String, dynamic>> fetchProducts({
    int page = 1,
    int perPage = 20,
    String? branchId,
    bool sellableOnly = false,
  }) async {
    _log('fetchProducts');
    return _handle('fetchProducts', {
      'page': page,
      'per_page': perPage,
      'branch_id': branchId,
    });
  }

  @override
  Future<Map<String, dynamic>?> lookupProductByBarcode(String code) async {
    _log('lookupProductByBarcode');
    return _handle('lookupProductByBarcode', {'code': code});
  }

  @override
  Future<Map<String, dynamic>> createSale(Map<String, dynamic> data) async {
    _log('createSale');
    return _handle('createSale', data);
  }

  @override
  Future<Map<String, dynamic>> fetchSales({
    int page = 1,
    int perPage = 20,
    String? branchId,
  }) async {
    _log('fetchSales');
    return _handle('fetchSales', {
      'page': page,
      'per_page': perPage,
      'branch_id': branchId,
    });
  }

  @override
  Future<Map<String, dynamic>> fetchSalesToday() async {
    _log('fetchSalesToday');
    return _handle('fetchSalesToday');
  }

  @override
  Future<String> uploadReceipt(XFile image) async {
    _log('uploadReceipt');
    return _handle('uploadReceipt', {'image': image.path}) as String;
  }

  @override
  Future<Map<String, dynamic>> fetchCustomers({
    int page = 1,
    int perPage = 20,
  }) async {
    _log('fetchCustomers');
    return _handle('fetchCustomers', {'page': page, 'per_page': perPage});
  }

  @override
  Future<Map<String, dynamic>> fetchCredits({
    String? status,
    int page = 1,
    int perPage = 20,
    String? branchId,
  }) async {
    _log('fetchCredits');
    return _handle('fetchCredits', {
      'status': status,
      'page': page,
      'per_page': perPage,
      'branch_id': branchId,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCreditsGroupedByCustomer({
    String? branchId,
  }) async {
    _log('fetchCreditsGroupedByCustomer');
    return List<Map<String, dynamic>>.from(
      _handle('fetchCreditsGroupedByCustomer', {'branch_id': branchId}),
    );
  }

  @override
  Future<Map<String, dynamic>> recordCreditPayment(
    String creditId,
    Map<String, dynamic> data,
  ) async {
    _log('recordCreditPayment');
    return _handle('recordCreditPayment', {'credit_uuid': creditId, ...data});
  }

  @override
  Future<Map<String, dynamic>?> fetchTableTabByLabel(String label) async {
    _log('fetchTableTabByLabel');
    return _handle('fetchTableTabByLabel', {'label': label});
  }

  @override
  Future<Map<String, dynamic>> upsertTableTab({
    required String label,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? employeeUuid,
    String? employeeName,
  }) async {
    _log('upsertTableTab');
    return _handle('upsertTableTab', {
      'label': label,
      'items': items,
      'customer_name': customerName,
      'employee_uuid': employeeUuid,
      'employee_name': employeeName,
    });
  }

  @override
  Future<Map<String, dynamic>> addItemsToTableTab({
    required String label,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? employeeName,
  }) async {
    _log('addItemsToTableTab');
    return _handle('addItemsToTableTab', {
      'label': label,
      'items': items,
      'customer_name': customerName,
      'employee_name': employeeName,
    });
  }

  @override
  Future<Map<String, dynamic>> closeOrder(
    String uuid,
    String paymentMethod,
  ) async {
    _log('closeOrder');
    return _handle('closeOrder', {
      'uuid': uuid,
      'payment_method': paymentMethod,
    });
  }

  @override
  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> data,
  ) async {
    _log('createProduct');
    return _handle('createProduct', data);
  }

  @override
  Future<Map<String, dynamic>> scanInvoice(File image) async {
    _log('scanInvoice');
    return _handle('scanInvoice', {'image': image.path});
  }

  @override
  Future<Map<String, dynamic>> updateProduct(
    String id,
    Map<String, dynamic> data,
  ) async {
    _log('updateProduct');
    return _handle('updateProduct', {'id': id, ...data});
  }

  @override
  Future<Map<String, dynamic>> restockProduct(
    String id,
    Map<String, dynamic> data,
  ) async {
    _log('restockProduct');
    return _handle('restockProduct', {'id': id, ...data});
  }

  @override
  Future<void> deleteProduct(String id) async {
    _log('deleteProduct');
    _handle('deleteProduct', {'id': id});
  }

  @override
  Future<Map<String, dynamic>> verifyPin({
    required String pin,
    required String employeeUuid,
  }) async {
    _log('verifyPin');
    return _handle('verifyPin', {'pin': pin, 'employee_uuid': employeeUuid});
  }

  @override
  Future<void> logout(String refreshToken) async {
    _log('logout');
    _handle('logout', {'refresh_token': refreshToken});
  }

  @override
  Future<Map<String, dynamic>> fetchStoreConfig() async {
    _log('fetchStoreConfig');
    return _handle('fetchStoreConfig');
  }

  @override
  Future<Map<String, dynamic>> fetchAnalyticsDashboard() async {
    _log('fetchAnalyticsDashboard');
    return _handle('fetchAnalyticsDashboard');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOpenAccounts() async {
    _log('fetchOpenAccounts');
    return List<Map<String, dynamic>>.from(_handle('fetchOpenAccounts'));
  }

  @override
  Future<Map<String, dynamic>> createCustomer(
    Map<String, dynamic> data,
  ) async {
    _log('createCustomer');
    return _handle('createCustomer', data);
  }

  @override
  Future<Map<String, dynamic>> updateCustomer(
    String id,
    Map<String, dynamic> data,
  ) async {
    _log('updateCustomer');
    return _handle('updateCustomer', {'id': id, ...data});
  }

  @override
  Future<Map<String, dynamic>> appendToFiado(String creditId, {
    required int totalAmount,
    String note = '',
  }) async {
    _log('appendToFiado');
    return _handle('appendToFiado', {
      'credit_id': creditId,
      'total_amount': totalAmount,
      'note': note,
    });
  }

  @override
  Future<Map<String, dynamic>> closeFiado(String creditId, {
    String reason = '',
    bool force = false,
  }) async {
    _log('closeFiado');
    return _handle('closeFiado', {
      'credit_id': creditId,
      'reason': reason,
      'force': force,
    });
  }

  @override
  Future<Map<String, dynamic>> removeItemFromTab(
    String orderUuid,
    String itemId,
  ) async {
    _log('removeItemFromTab');
    return _handle('removeItemFromTab', {
      'order_uuid': orderUuid,
      'item_id': itemId,
    });
  }

  @override
  Future<Map<String, dynamic>> fetchPublicTableSession(
    String sessionToken,
  ) async {
    _log('fetchPublicTableSession');
    return _handle('fetchPublicTableSession', {'session_token': sessionToken});
  }

  @override
  Future<Map<String, dynamic>> registerPartialPayment({
    required String orderId,
    required double amount,
    required String paymentMethod,
    String paymentMethodId = '',
    String notes = '',
    String? receiptImageUrl,
  }) async {
    _log('registerPartialPayment');
    return _handle('registerPartialPayment', {
      'order_id': orderId,
      'amount': amount,
      'payment_method': paymentMethod,
      'payment_method_id': paymentMethodId,
      'notes': notes,
      'receipt_image_url': receiptImageUrl,
    });
  }

  @override
  Future<Map<String, dynamic>> confirmPartialPayment(
    String paymentId,
  ) async {
    _log('confirmPartialPayment');
    return _handle('confirmPartialPayment', {'payment_id': paymentId});
  }

  @override
  Future<Map<String, dynamic>> lookupBarcode(String barcode) async {
    _log('lookupBarcode');
    return _handle('lookupBarcode', {'barcode': barcode});
  }

  @override
  Future<List<Map<String, dynamic>>> voiceInventory({
    required Uint8List audioBytes,
    required String mimeType,
    String filename = 'vendia_voice',
  }) async {
    _log('voiceInventory');
    return List<Map<String, dynamic>>.from(
      _handle('voiceInventory', {
        'audio_bytes': audioBytes.length,
        'mime_type': mimeType,
        'filename': filename,
      }),
    );
  }
}
