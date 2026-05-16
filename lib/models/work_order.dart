// Spec: specs/003-trabajos-muebles/spec.md
//
// Modelos WorkOrder + WorkOrderItem + WorkOrderPayment (trabajo de
// fabricación/reparación de muebles) — Feature 003.
//
// Un trabajo (`WorkOrder`) es un encargo del cliente: nace como
// cotización, lleva ítems de material y mano de obra, recibe anticipos
// del cliente y avanza por un ciclo de vida hasta entregarse. Al pasar a
// `terminada` los materiales descuentan stock vía kardex en el backend
// (spec §1, plan §3).
//
// Lección de F1 (BUG-5/6): el backend Go embebe `BaseModel`, cuya llave
// primaria UUID se serializa como `id` — NUNCA `uuid`. `fromJson` lee
// `id` como fuente autoritativa y deja `uuid` como respaldo para datos
// locales viejos guardados con la llave antigua.

/// Un ítem de trabajo: una línea de material (referencia un insumo XOR un
/// producto) o de mano de obra (solo descripción + precio) — FR-02.
class WorkOrderItem {
  /// Ítem de material: descuenta inventario al `terminada` el trabajo.
  static const String kindMaterial = 'material';

  /// Ítem de mano de obra: no toca inventario.
  static const String kindLabor = 'mano_obra';

  /// Etiquetas legibles en español de cada tipo de ítem (Art. V).
  static const Map<String, String> kindLabels = {
    kindMaterial: 'Material',
    kindLabor: 'Mano de obra',
  };

  final String uuid;

  /// `material` | `mano_obra`.
  final String kind;

  /// FK al insumo (`Ingredient`). Solo para materiales; nulo si no aplica.
  final String? ingredientId;

  /// FK al producto (`Product`). Solo para materiales; nulo si no aplica.
  final String? productId;

  /// Descripción de la línea — para mano de obra es el texto del trabajo;
  /// para material es el nombre del insumo/producto.
  final String description;

  final double quantity;

  /// Precio unitario en COP de esta línea del trabajo.
  final double unitPrice;

  WorkOrderItem({
    String? uuid,
    required this.kind,
    this.ingredientId,
    this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
  }) : uuid = uuid ?? '';

  /// Total de la línea: cantidad × precio unitario (FR-02, AC-01).
  double get lineTotal => quantity * unitPrice;

  /// `true` si la línea es de material.
  bool get isMaterial => kind == kindMaterial;

  /// `true` si la línea es de mano de obra.
  bool get isLabor => kind == kindLabor;

  /// `true` si el material referencia un insumo (vs un producto).
  bool get isIngredient =>
      ingredientId != null && ingredientId!.isNotEmpty;

  /// Etiqueta legible del tipo de ítem en español.
  String get kindLabel => kindLabels[kind] ?? kind;

  /// Invariante FR-02 / spec §7: un `material` referencia exactamente un
  /// insumo XOR un producto; una `mano_obra` no referencia inventario.
  /// Cantidad y precio siempre positivos (caso borde §9).
  bool get isValid {
    final hasIngredient = ingredientId != null && ingredientId!.isNotEmpty;
    final hasProduct = productId != null && productId!.isNotEmpty;
    if (quantity <= 0 || unitPrice <= 0) return false;
    if (isMaterial) {
      return hasIngredient != hasProduct; // XOR
    }
    if (isLabor) {
      return !hasIngredient && !hasProduct;
    }
    return false;
  }

  factory WorkOrderItem.fromJson(Map<String, dynamic> json) {
    // El backend embebe `BaseModel` → la llave primaria es `id` (BUG-5).
    final id = (json['id'] ?? json['uuid']) as String?;
    return WorkOrderItem(
      uuid: id ?? '',
      kind: json['kind'] as String? ?? kindMaterial,
      ingredientId: json['ingredient_id'] as String?,
      productId: json['product_id'] as String?,
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Serializa el ítem para el cuerpo de `POST /api/v1/work-orders`.
  /// Las FK nulas se omiten para no enviar strings vacíos que rompan el
  /// insert en Postgres (Art. X — `*string` + `middleware.UUIDPtr`).
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'kind': kind,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
    };
    if (isMaterial) {
      if (ingredientId != null && ingredientId!.isNotEmpty) {
        json['ingredient_id'] = ingredientId;
      }
      if (productId != null && productId!.isNotEmpty) {
        json['product_id'] = productId;
      }
    }
    return json;
  }

  /// Copia inmutable con los campos indicados sobreescritos (Art. IX).
  WorkOrderItem copyWith({
    String? uuid,
    String? kind,
    String? ingredientId,
    String? productId,
    String? description,
    double? quantity,
    double? unitPrice,
  }) {
    return WorkOrderItem(
      uuid: uuid ?? this.uuid,
      kind: kind ?? this.kind,
      ingredientId: ingredientId ?? this.ingredientId,
      productId: productId ?? this.productId,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}

/// Un anticipo del cliente contra un trabajo (FR-04). Tabla propia,
/// desacoplada de `OrderTicket` (spec D3).
class WorkOrderPayment {
  final String uuid;
  final double amount;

  /// Método de pago: `efectivo` | `nequi` | `daviplata` | `transferencia`.
  final String method;
  final DateTime? paidAt;

  WorkOrderPayment({
    String? uuid,
    required this.amount,
    required this.method,
    this.paidAt,
  }) : uuid = uuid ?? '';

  factory WorkOrderPayment.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['uuid']) as String?;
    return WorkOrderPayment(
      uuid: id ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      method: json['method'] as String? ?? 'efectivo',
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'] as String)
          : null,
    );
  }

  /// Serializa el cuerpo de `POST /api/v1/work-orders/:uuid/payments`.
  Map<String, dynamic> toJson() => {
        'amount': amount,
        'method': method,
      };
}

/// Un trabajo de fabricación o reparación de muebles. Ciclo de vida:
/// `cotizacion → aprobada → en_proceso → terminada → entregada`
/// (+ `cancelada`) — solo transiciones válidas (FR-03, spec §7).
class WorkOrder {
  // ── Tipos de trabajo (FR-01) ───────────────────────────────────────
  static const String typeManufacture = 'fabricacion';
  static const String typeRepair = 'reparacion';

  /// Etiquetas legibles en español de cada tipo (Art. V).
  static const Map<String, String> typeLabels = {
    typeManufacture: 'Fabricación',
    typeRepair: 'Reparación',
  };

  // ── Estados del ciclo de vida (FR-03) ──────────────────────────────
  static const String statusQuote = 'cotizacion';
  static const String statusApproved = 'aprobada';
  static const String statusInProgress = 'en_proceso';
  static const String statusDone = 'terminada';
  static const String statusDelivered = 'entregada';
  static const String statusCanceled = 'cancelada';

  /// Etiquetas legibles en español de cada estado (Art. V).
  static const Map<String, String> statusLabels = {
    statusQuote: 'Cotización',
    statusApproved: 'Aprobada',
    statusInProgress: 'En proceso',
    statusDone: 'Terminada',
    statusDelivered: 'Entregada',
    statusCanceled: 'Cancelada',
  };

  /// Secuencia lineal del ciclo de vida. `entregada` y `cancelada` son
  /// terminales — no aparecen como origen de un avance (spec §7).
  static const List<String> _lifecycle = [
    statusQuote,
    statusApproved,
    statusInProgress,
    statusDone,
    statusDelivered,
  ];

  final String uuid;
  final String customerId;

  /// `fabricacion` | `reparacion`.
  final String type;
  final String status;
  final String description;

  /// Total del trabajo en COP — el backend lo calcula como Σ de ítems.
  final double total;

  /// Suma de los anticipos del cliente — calculado por el backend (FR-04).
  final double paid;

  /// Saldo pendiente: `total - abonado` — calculado por el backend.
  final double balance;

  final String? notes;
  final DateTime? approvedAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final List<WorkOrderItem> items;
  final List<WorkOrderPayment> payments;
  final DateTime createdAt;

  WorkOrder({
    required this.uuid,
    required this.customerId,
    required this.type,
    required this.status,
    required this.description,
    double? total,
    double? paid,
    double? balance,
    this.notes,
    this.approvedAt,
    this.completedAt,
    this.deliveredAt,
    this.items = const [],
    this.payments = const [],
    DateTime? createdAt,
  })  : total = total ?? 0,
        paid = paid ?? 0,
        balance = balance ?? 0,
        createdAt = createdAt ?? DateTime.now();

  /// Total calculado sumando los ítems — útil mientras se arma el trabajo
  /// en el formulario, antes de que el backend persista `total`.
  double get computedTotal =>
      items.fold<double>(0, (sum, it) => sum + it.lineTotal);

  /// El trabajo solo se edita en `cotizacion` o `aprobada` (FR-07, AC-07).
  bool get isEditable =>
      status == statusQuote || status == statusApproved;

  /// `entregada` y `cancelada` son terminales — sin más transiciones.
  bool get isTerminal =>
      status == statusDelivered || status == statusCanceled;

  /// Solo un trabajo en `cotizacion` se comparte por WhatsApp (AC-06).
  bool get canShare => status == statusQuote;

  /// Siguiente estado del ciclo de vida lineal; `null` si es terminal.
  String? get nextStatus {
    final i = _lifecycle.indexOf(status);
    if (i < 0 || i >= _lifecycle.length - 1) return null;
    return _lifecycle[i + 1];
  }

  /// Se puede avanzar el trabajo si hay un siguiente estado y tiene al
  /// menos un ítem — un trabajo sin ítems no pasa a `aprobada` (caso
  /// borde §9).
  bool get canAdvance => nextStatus != null && items.isNotEmpty;

  /// Se puede cancelar mientras el trabajo no esté en estado terminal.
  bool get canCancel => !isTerminal;

  /// Etiqueta legible del estado en español.
  String get statusLabel => statusLabels[status] ?? status;

  /// Etiqueta legible del tipo en español.
  String get typeLabel => typeLabels[type] ?? type;

  /// Valida una transición de estado contra la máquina del ciclo de vida
  /// (FR-03, AC-05). Solo se acepta avanzar un paso o cancelar desde un
  /// estado no terminal.
  static bool isValidTransition(String from, String to) {
    if (from == statusDelivered || from == statusCanceled) return false;
    if (to == statusCanceled) return true;
    final fromIndex = _lifecycle.indexOf(from);
    final toIndex = _lifecycle.indexOf(to);
    if (fromIndex < 0 || toIndex < 0) return false;
    return toIndex == fromIndex + 1;
  }

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    // El backend embebe `BaseModel` → la llave primaria es `id` (BUG-5).
    final id = (json['id'] ?? json['uuid']) as String?;
    if (id == null) {
      throw const FormatException(
        'El trabajo del servidor no trae identificador (id/uuid).',
      );
    }
    final rawItems = (json['items'] as List?) ?? const [];
    final rawPayments = (json['payments'] as List?) ?? const [];
    final items = rawItems
        .cast<Map<String, dynamic>>()
        .map(WorkOrderItem.fromJson)
        .toList();
    final payments = rawPayments
        .cast<Map<String, dynamic>>()
        .map(WorkOrderPayment.fromJson)
        .toList();

    final total = (json['total'] as num?)?.toDouble() ?? 0;
    // El backend calcula `abonado`/`saldo`; si aún no llegan (datos
    // armados offline), se derivan del total y la suma de pagos.
    final paidFromPayments =
        payments.fold<double>(0, (sum, p) => sum + p.amount);
    final paid = (json['abonado'] as num?)?.toDouble() ?? paidFromPayments;
    final balance =
        (json['saldo'] as num?)?.toDouble() ?? (total - paid);

    return WorkOrder(
      uuid: id,
      customerId: json['customer_id'] as String? ?? '',
      type: json['type'] as String? ?? typeManufacture,
      status: json['status'] as String? ?? statusQuote,
      description: json['description'] as String? ?? '',
      total: total,
      paid: paid,
      balance: balance,
      notes: json['notes'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.tryParse(json['approved_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'] as String)
          : null,
      items: items,
      payments: payments,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Serializa el cuerpo de `POST /api/v1/work-orders` (plan §4):
  /// `{id?, customer_id, type, description, notes?, items:[...]}`. El `id`
  /// lo genera el cliente para que reenviar la operación sea idempotente
  /// (Art. II). `notes` se omite cuando es nulo para no enviar strings
  /// vacíos (Art. X).
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': uuid,
      'customer_id': customerId,
      'type': type,
      'description': description,
      'items': items.map((it) => it.toJson()).toList(),
    };
    if (notes != null && notes!.isNotEmpty) {
      json['notes'] = notes;
    }
    return json;
  }

  /// Copia inmutable con los campos indicados sobreescritos (Art. IX).
  WorkOrder copyWith({
    String? uuid,
    String? customerId,
    String? type,
    String? status,
    String? description,
    double? total,
    double? paid,
    double? balance,
    String? notes,
    DateTime? approvedAt,
    DateTime? completedAt,
    DateTime? deliveredAt,
    List<WorkOrderItem>? items,
    List<WorkOrderPayment>? payments,
    DateTime? createdAt,
  }) {
    return WorkOrder(
      uuid: uuid ?? this.uuid,
      customerId: customerId ?? this.customerId,
      type: type ?? this.type,
      status: status ?? this.status,
      description: description ?? this.description,
      total: total ?? this.total,
      paid: paid ?? this.paid,
      balance: balance ?? this.balance,
      notes: notes ?? this.notes,
      approvedAt: approvedAt ?? this.approvedAt,
      completedAt: completedAt ?? this.completedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      items: items ?? this.items,
      payments: payments ?? this.payments,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
