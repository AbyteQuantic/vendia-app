/// Order ticket model for VendIA collaborative selling (Waiter + Cashier).
/// Agnostic: works for tables (Mesa 4), turns (Turno 15), or delivery.
class OrderTicket {
  final String uuid;
  final String label; // "Mesa 4", "Turno 15", "Juan (Para llevar)"
  final String? customerName;
  final String? employeeUuid; // Waiter who created it
  final String? employeeName;
  final OrderStatus status;
  final OrderType type;
  final List<OrderItem> items;
  final double total;
  final String? deliveryAddress;
  final String? customerPhone;
  final String? paymentMethod;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? serverId;

  // ── Spec 105 — timestamps de transición y mostrador prepago ──
  final DateTime? preparandoAt;
  final DateTime? listoAt;
  final DateTime? entregadoAt;
  final DateTime? paidAt;
  final String? saleUuid;

  OrderTicket({
    required this.uuid,
    required this.label,
    this.customerName,
    this.employeeUuid,
    this.employeeName,
    this.status = OrderStatus.nuevo,
    this.type = OrderType.mesa,
    this.items = const [],
    this.total = 0,
    this.deliveryAddress,
    this.customerPhone,
    this.paymentMethod,
    DateTime? createdAt,
    this.updatedAt,
    this.serverId,
    this.preparandoAt,
    this.listoAt,
    this.entregadoAt,
    this.paidAt,
    this.saleUuid,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Calculate total from items
  double get calculatedTotal =>
      items.fold(0.0, (sum, item) => sum + item.subtotal);

  /// Number of items
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Spec 105 — tiempo objetivo del ticket: el MAX de los duration_min de
  /// sus ítems (la cocina paraleliza). Null si ningún ítem lo tiene.
  int? get maxDurationMin {
    int? max;
    for (final item in items) {
      final d = item.durationMin;
      if (d != null && (max == null || d > max)) max = d;
    }
    return max;
  }

  /// Spec 105 — mostrador PREPAGO: la venta ya se registró en el POS;
  /// el ticket muere en 'entregado', jamás pasa por cobrar.
  bool get isPrepaid => paidAt != null;

  /// Time since creation
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    return 'Hace ${diff.inHours}h ${diff.inMinutes % 60}min';
  }

  /// Status badge text in Spanish
  String get statusLabel {
    switch (status) {
      case OrderStatus.nuevo:
        return 'Nuevo';
      case OrderStatus.preparando:
        return 'Preparando';
      case OrderStatus.listo:
        return 'Listo';
      case OrderStatus.entregado:
        return 'Entregado';
      case OrderStatus.cobrado:
        return 'Cobrado';
      case OrderStatus.cancelado:
        return 'Cancelado';
    }
  }

  factory OrderTicket.fromJson(Map<String, dynamic> json) {
    return OrderTicket(
      uuid: json['uuid'] as String,
      label: json['label'] as String,
      customerName: json['customer_name'] as String?,
      employeeUuid: json['employee_uuid'] as String?,
      employeeName: json['employee_name'] as String?,
      status: OrderStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OrderStatus.nuevo,
      ),
      type: OrderType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => OrderType.mesa,
      ),
      items: (json['items'] as List?)
              ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: (json['total'] as num?)?.toDouble() ?? 0,
      deliveryAddress: json['delivery_address'] as String?,
      customerPhone: json['customer_phone'] as String?,
      paymentMethod: json['payment_method'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      serverId: json['id'] is int ? json['id'] as int : null,
      preparandoAt: _parseDate(json['preparando_at']),
      listoAt: _parseDate(json['listo_at']),
      entregadoAt: _parseDate(json['entregado_at']),
      paidAt: _parseDate(json['paid_at']),
      saleUuid: json['sale_uuid'] as String?,
    );
  }

  /// Parsea la fila cruda del backend Go (GET /orders): la clave primaria
  /// llega como `id` (uuid string) y no existe `uuid`.
  factory OrderTicket.fromApi(Map<String, dynamic> json) {
    return OrderTicket.fromJson({
      ...json,
      'uuid': (json['id'] as String?) ?? (json['uuid'] as String?) ?? '',
      'id': null,
    });
  }

  static DateTime? _parseDate(dynamic v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'label': label,
        'customer_name': customerName,
        'employee_uuid': employeeUuid,
        'employee_name': employeeName,
        'status': status.name,
        'type': type.name,
        'items': items.map((e) => e.toJson()).toList(),
        'total': calculatedTotal,
        'delivery_address': deliveryAddress,
        'customer_phone': customerPhone,
        'payment_method': paymentMethod,
      };

  OrderTicket copyWith({
    OrderStatus? status,
    List<OrderItem>? items,
    String? paymentMethod,
  }) {
    return OrderTicket(
      uuid: uuid,
      label: label,
      customerName: customerName,
      employeeUuid: employeeUuid,
      employeeName: employeeName,
      status: status ?? this.status,
      type: type,
      items: items ?? this.items,
      total: total,
      deliveryAddress: deliveryAddress,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      serverId: serverId,
      preparandoAt: preparandoAt,
      listoAt: listoAt,
      entregadoAt: entregadoAt,
      paidAt: paidAt,
      saleUuid: saleUuid,
    );
  }
}

class OrderItem {
  final String productUuid;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String? emoji;

  // ── Spec 105 ──
  /// Indicación del cliente ("sin cebolla"). La cocina la ve resaltada.
  final String? notes;

  /// Snapshot del tiempo de preparación (min) congelado al crear el pedido
  /// (patrón anti-drift Spec 083). Null si el producto no lo define.
  final int? durationMin;

  OrderItem({
    required this.productUuid,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.emoji,
    this.notes,
    this.durationMin,
  });

  double get subtotal => quantity * unitPrice;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productUuid: json['product_uuid'] as String,
      productName: json['product_name'] as String,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      emoji: json['emoji'] as String?,
      notes: (json['notes'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['notes'] as String).trim(),
      // 0 = "sin tiempo definido" → null, para que el KDS use su default.
      durationMin: ((json['duration_min'] as num?)?.toInt() ?? 0) > 0
          ? (json['duration_min'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'product_uuid': productUuid,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'emoji': emoji,
        if (notes != null) 'notes': notes,
        if (durationMin != null) 'duration_min': durationMin,
      };
}

enum OrderStatus { nuevo, preparando, listo, entregado, cobrado, cancelado }

enum OrderType { mesa, turno, paraLlevar, domicilioWeb }
