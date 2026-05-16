// Spec: specs/002-ordenes-compra/spec.md
//
// Modelos PurchaseOrder + PurchaseOrderItem (orden de compra) — Feature 002.
//
// Una orden de compra (PO) es un pedido a un proveedor con sus ítems.
// Cierra el ciclo proveedor → pedido → recepción → inventario: al recibir
// la PO, cada ítem entra stock vía un movimiento de kardex
// `purchase_receipt` (spec §1, plan §3).
//
// Lección de F1 (BUG-5/6): el backend Go embebe `BaseModel`, cuya llave
// primaria UUID se serializa como `id` — NUNCA `uuid`. `fromJson` lee `id`
// como fuente autoritativa y deja `uuid` como respaldo para datos locales
// viejos guardados con la llave antigua.

/// Un ítem de orden de compra referencia un insumo XOR un producto (D1).
class PurchaseOrderItem {
  final String uuid;

  /// FK al insumo (`Ingredient`). Nulo si el ítem es un producto.
  final String? ingredientId;

  /// FK al producto (`Product`). Nulo si el ítem es un insumo.
  final String? productId;

  /// Snapshot del nombre al momento de armar la PO (FR-02): sobrevive a
  /// que el insumo/producto se renombre o se borre.
  final String nameSnapshot;

  final double quantity;

  /// Costo unitario en COP de este ítem para esta orden.
  final double unitCost;

  PurchaseOrderItem({
    String? uuid,
    this.ingredientId,
    this.productId,
    required this.nameSnapshot,
    required this.quantity,
    required this.unitCost,
  }) : uuid = uuid ?? '';

  /// Total de la línea: cantidad × costo unitario (FR-01).
  double get lineTotal => quantity * unitCost;

  /// Invariante D1: referencia exactamente un insumo XOR un producto, y
  /// tanto la cantidad como el costo son positivos (caso borde §9).
  bool get isValid {
    final hasIngredient = ingredientId != null && ingredientId!.isNotEmpty;
    final hasProduct = productId != null && productId!.isNotEmpty;
    final xor = hasIngredient != hasProduct;
    return xor && quantity > 0 && unitCost > 0;
  }

  /// `true` si el ítem es un insumo; `false` si es un producto.
  bool get isIngredient =>
      ingredientId != null && ingredientId!.isNotEmpty;

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['uuid']) as String?;
    return PurchaseOrderItem(
      uuid: id ?? '',
      ingredientId: json['ingredient_id'] as String?,
      productId: json['product_id'] as String?,
      nameSnapshot: json['name_snapshot'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Serializa el ítem para el cuerpo de `POST /api/v1/purchase-orders`.
  /// Las FK nulas se omiten para no enviar strings vacíos que rompan el
  /// insert en Postgres (Art. X — `*string` + `middleware.UUIDPtr`).
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'name_snapshot': nameSnapshot,
      'quantity': quantity,
      'unit_cost': unitCost,
    };
    if (ingredientId != null && ingredientId!.isNotEmpty) {
      json['ingredient_id'] = ingredientId;
    }
    if (productId != null && productId!.isNotEmpty) {
      json['product_id'] = productId;
    }
    return json;
  }

  /// Copia inmutable con los campos indicados sobreescritos (Art. IX).
  PurchaseOrderItem copyWith({
    String? uuid,
    String? ingredientId,
    String? productId,
    String? nameSnapshot,
    double? quantity,
    double? unitCost,
  }) {
    return PurchaseOrderItem(
      uuid: uuid ?? this.uuid,
      ingredientId: ingredientId ?? this.ingredientId,
      productId: productId ?? this.productId,
      nameSnapshot: nameSnapshot ?? this.nameSnapshot,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
    );
  }
}

/// Una orden de compra a un proveedor. Ciclo de vida:
/// `borrador → enviada → recibida` (+ `cancelada`) — solo transiciones
/// válidas (FR-03, spec §7).
class PurchaseOrder {
  /// Estado borrador: se puede editar, enviar, recibir o cancelar.
  static const String statusDraft = 'borrador';

  /// Estado enviada: se puede recibir o cancelar; no editar.
  static const String statusSent = 'enviada';

  /// Estado recibida: terminal — el stock ya entró por kardex.
  static const String statusReceived = 'recibida';

  /// Estado cancelada: terminal — no afecta stock.
  static const String statusCanceled = 'cancelada';

  /// Etiquetas legibles en español de cada estado (Art. V).
  static const Map<String, String> statusLabels = {
    statusDraft: 'Borrador',
    statusSent: 'Enviada',
    statusReceived: 'Recibida',
    statusCanceled: 'Cancelada',
  };

  final String uuid;
  final String supplierId;
  final String status;
  final double total;
  final String? notes;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final List<PurchaseOrderItem> items;
  final DateTime createdAt;

  PurchaseOrder({
    required this.uuid,
    required this.supplierId,
    required this.status,
    this.total = 0,
    this.notes,
    this.sentAt,
    this.receivedAt,
    this.items = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Total calculado sumando los ítems — útil mientras se arma la PO en
  /// el formulario, antes de que el backend persista `total`.
  double get computedTotal =>
      items.fold<double>(0, (sum, it) => sum + it.lineTotal);

  /// La PO solo se edita en `borrador` (plan §4).
  bool get isEditable => status == statusDraft;

  /// Una PO `recibida` o `cancelada` es terminal (spec §7).
  bool get isTerminal =>
      status == statusReceived || status == statusCanceled;

  /// Se puede enviar una PO en `borrador` que tenga al menos un ítem.
  /// Una PO sin ítems no se puede enviar (caso borde §9).
  bool get canSend => status == statusDraft && items.isNotEmpty;

  /// Se puede recibir desde `borrador` o `enviada` (D3) con ítems.
  bool get canReceive =>
      (status == statusDraft || status == statusSent) && items.isNotEmpty;

  /// Se puede cancelar solo desde `borrador` o `enviada` (AC-06).
  bool get canCancel =>
      status == statusDraft || status == statusSent;

  /// Etiqueta legible del estado en español.
  String get statusLabel => statusLabels[status] ?? status;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    // El backend embebe `BaseModel` → la llave primaria es `id` (BUG-5).
    final id = (json['id'] ?? json['uuid']) as String?;
    if (id == null) {
      throw const FormatException(
        'La orden de compra del servidor no trae identificador (id/uuid).',
      );
    }
    final rawItems = (json['items'] as List?) ?? const [];
    return PurchaseOrder(
      uuid: id,
      supplierId: json['supplier_id'] as String? ?? '',
      status: json['status'] as String? ?? statusDraft,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at'] as String)
          : null,
      receivedAt: json['received_at'] != null
          ? DateTime.tryParse(json['received_at'] as String)
          : null,
      items: rawItems
          .cast<Map<String, dynamic>>()
          .map(PurchaseOrderItem.fromJson)
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Serializa el cuerpo de `POST /api/v1/purchase-orders` (plan §4):
  /// `{id?, supplier_id, notes?, items:[...]}`. El `id` lo genera el
  /// cliente para que reenviar la operación sea idempotente (Art. II).
  /// `notes` se omite cuando es nulo para no enviar strings vacíos.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': uuid,
      'supplier_id': supplierId,
      'items': items.map((it) => it.toJson()).toList(),
    };
    if (notes != null && notes!.isNotEmpty) {
      json['notes'] = notes;
    }
    return json;
  }

  /// Copia inmutable con los campos indicados sobreescritos (Art. IX).
  PurchaseOrder copyWith({
    String? uuid,
    String? supplierId,
    String? status,
    double? total,
    String? notes,
    DateTime? sentAt,
    DateTime? receivedAt,
    List<PurchaseOrderItem>? items,
    DateTime? createdAt,
  }) {
    return PurchaseOrder(
      uuid: uuid ?? this.uuid,
      supplierId: supplierId ?? this.supplierId,
      status: status ?? this.status,
      total: total ?? this.total,
      notes: notes ?? this.notes,
      sentAt: sentAt ?? this.sentAt,
      receivedAt: receivedAt ?? this.receivedAt,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
