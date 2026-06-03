Map<String, dynamic> saleCompleted({
  String uuid = 'sale-default-uuid',
  double total = 50000,
  double cashAmount = 50000,
  double changeDue = 0,
  String paymentMethod = 'cash',
  String status = 'completed',
}) {
  return {
    'uuid': uuid,
    'total': total,
    'cash_amount': cashAmount,
    'change_due': changeDue,
    'payment_method': paymentMethod,
    'status': status,
    'items': [
      {
        'product_id': 'prod-1',
        'name': 'Arroz Diana 1kg',
        'quantity': 2,
        'unit_price': 3200,
        'subtotal': 6400,
      },
      {
        'product_id': 'prod-2',
        'name': 'Aceite Gourmet 900ml',
        'quantity': 1,
        'unit_price': 12400,
        'subtotal': 12400,
      },
    ],
    'created_at': DateTime.now().toIso8601String(),
  };
}

Map<String, dynamic> productDefault({
  String id = 'prod-default',
  String name = 'Producto Test',
  double price = 10000,
  int stock = 10,
  String barcode = '7700000000000',
  String category = 'General',
}) {
  return {
    'id': id,
    'name': name,
    'price': price,
    'stock': stock,
    'barcode': barcode,
    'category': category,
  };
}

Map<String, dynamic> customerDefault({
  String uuid = 'cust-default',
  String name = 'Cliente Test',
  String phone = '3000000000',
  double totalDebt = 0,
}) {
  return {
    'uuid': uuid,
    'name': name,
    'phone': phone,
    'total_debt': totalDebt,
  };
}

Map<String, dynamic> creditDefault({
  String uuid = 'credit-default',
  String customerUuid = 'cust-default',
  String customerName = 'Cliente Test',
  double total = 50000,
  double paid = 20000,
  double balance = 30000,
  String status = 'active',
}) {
  return {
    'uuid': uuid,
    'customer_uuid': customerUuid,
    'customer_name': customerName,
    'total': total,
    'paid': paid,
    'balance': balance,
    'status': status,
  };
}

Map<String, dynamic> tabDefault({
  String uuid = 'tab-default',
  String label = 'Mesa 1',
  List<Map<String, dynamic>> items = const [],
  double total = 0,
  String status = 'open',
}) {
  return {
    'uuid': uuid,
    'label': label,
    'items': items,
    'total': total,
    'status': status,
  };
}

Map<String, dynamic> authResponse({
  String accessToken = 'mock-access-token',
  String refreshToken = 'mock-refresh-token',
  String tenantUuid = 'tenant-1',
  String tenantName = 'Test Tienda',
  String employeeUuid = 'emp-1',
  String employeeName = 'Test Cashier',
}) {
  return {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'tenant': {'uuid': tenantUuid, 'name': tenantName},
    'employee': {'uuid': employeeUuid, 'name': employeeName},
  };
}

List<Map<String, dynamic>> defaultBranches() {
  return [
    {'id': 'branch-1', 'name': 'Sede Principal', 'is_active': true},
    {'id': 'branch-2', 'name': 'Sede Secundaria', 'is_active': true},
  ];
}
