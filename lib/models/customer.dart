// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// Modelos inmutables del dominio "gestión de clientes" (F030).
//
// [Customer] es la vista agregada que devuelve GET /api/v1/customers:
// el registro base (id/name/phone) + los agregados calculados desde
// `sales` (total gastado, número de compras, última compra).
//
// [CustomerSale] es una venta del historial — la línea de la timeline
// en el detalle del cliente.
//
// [CustomerHistory] empaqueta la respuesta de
// GET /api/v1/customers/:id/history (cliente + summary + ventas).
//
// El registro Customer es el MISMO concepto que el cliente del flujo
// de fiar (modelo backend `Customer`); aquí solo lo modelamos con los
// campos que la UI de F030 necesita.

/// Cliente con sus agregados de compra. Lo que la lista "Mis clientes"
/// pinta en cada tarjeta.
class Customer {
  /// UUID del cliente (string — el backend usa uuid). Vacío solo en
  /// estados transitorios; los registros del servidor siempre lo traen.
  final String id;
  final String name;
  final String phone;

  /// Suma histórica del total de todas las ventas asociadas al cliente.
  final double totalSpent;

  /// Número de ventas asociadas al cliente.
  final int purchaseCount;

  /// Fecha de la última compra. Null si el cliente aún no tiene ventas
  /// (recién registrado).
  final DateTime? lastPurchaseAt;

  /// Fecha de creación del registro del cliente.
  final DateTime? createdAt;

  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.totalSpent = 0,
    this.purchaseCount = 0,
    this.lastPurchaseAt,
    this.createdAt,
  });

  /// True cuando el cliente nunca ha registrado una compra.
  bool get hasNoPurchases => purchaseCount == 0;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      // El backend puede devolver el id como `id` (uuid string).
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      totalSpent: (json['total_spent'] as num? ?? 0).toDouble(),
      purchaseCount: (json['purchase_count'] as num? ?? 0).toInt(),
      lastPurchaseAt: _parseDate(json['last_purchase_at']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'total_spent': totalSpent,
        'purchase_count': purchaseCount,
        if (lastPurchaseAt != null)
          'last_purchase_at': lastPurchaseAt!.toIso8601String(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    double? totalSpent,
    int? purchaseCount,
    DateTime? lastPurchaseAt,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      totalSpent: totalSpent ?? this.totalSpent,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      lastPurchaseAt: lastPurchaseAt ?? this.lastPurchaseAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Una venta del historial de un cliente.
class CustomerSale {
  final String id;
  final double total;
  final DateTime? createdAt;
  final int itemsCount;
  final String paymentMethod;

  const CustomerSale({
    required this.id,
    this.total = 0,
    this.createdAt,
    this.itemsCount = 0,
    this.paymentMethod = '',
  });

  factory CustomerSale.fromJson(Map<String, dynamic> json) {
    return CustomerSale(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      total: (json['total'] as num? ?? 0).toDouble(),
      createdAt: _parseDate(json['created_at']),
      itemsCount: (json['items_count'] as num? ?? 0).toInt(),
      paymentMethod: (json['payment_method'] as String?) ?? '',
    );
  }
}

/// Resumen agregado del historial de un cliente.
class CustomerSummary {
  final double totalSpent;
  final int purchaseCount;
  final DateTime? firstPurchaseAt;
  final DateTime? lastPurchaseAt;

  const CustomerSummary({
    this.totalSpent = 0,
    this.purchaseCount = 0,
    this.firstPurchaseAt,
    this.lastPurchaseAt,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    return CustomerSummary(
      totalSpent: (json['total_spent'] as num? ?? 0).toDouble(),
      purchaseCount: (json['purchase_count'] as num? ?? 0).toInt(),
      firstPurchaseAt: _parseDate(json['first_purchase_at']),
      lastPurchaseAt: _parseDate(json['last_purchase_at']),
    );
  }
}

/// Respuesta completa de GET /api/v1/customers/:id/history.
class CustomerHistory {
  final Customer customer;
  final CustomerSummary summary;
  final List<CustomerSale> sales;

  const CustomerHistory({
    required this.customer,
    required this.summary,
    this.sales = const [],
  });

  factory CustomerHistory.fromJson(Map<String, dynamic> json) {
    final rawCustomer =
        (json['customer'] as Map<String, dynamic>?) ?? const {};
    final rawSummary = (json['summary'] as Map<String, dynamic>?) ?? const {};
    final rawSales = (json['sales'] as List?) ?? const [];
    return CustomerHistory(
      customer: Customer.fromJson(rawCustomer),
      summary: CustomerSummary.fromJson(rawSummary),
      sales: rawSales
          .whereType<Map<String, dynamic>>()
          .map(CustomerSale.fromJson)
          .toList(growable: false),
    );
  }
}

/// Parsea una fecha ISO-8601 de forma defensiva. Devuelve null ante
/// cualquier valor ausente, vacío o malformado — nunca lanza.
DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
