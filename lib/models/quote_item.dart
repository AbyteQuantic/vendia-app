// Spec: specs/031-cotizaciones/spec.md
//
// Modelo inmutable de una línea de cotización (F031).
//
// Una [QuoteItem] es un renglón de la cotización: puede venir de un
// producto del inventario (`productId` != null) o ser una línea libre
// escrita a mano (`productId` == null) — ej. "Mano de obra".
//
// Espejo del modelo backend `QuoteItem` (plan §3): name, quantity,
// unitPrice, discount, subtotal. El `subtotal` lo calcula el servidor
// pero el modelo expone [computedSubtotal] para que el formulario
// muestre totales en vivo sin depender de un round-trip.

/// Una línea de cotización — producto del inventario o línea libre.
class QuoteItem {
  /// UUID del producto del inventario. Null cuando es una línea libre.
  final String? productId;

  /// Nombre visible de la línea. Para productos del inventario es el
  /// nombre del producto; para líneas libres lo escribe el dueño.
  final String name;

  /// Cantidad. `double` porque el negocio puede cotizar fraccionados
  /// (ej. 2.5 metros de cable) — igual que el resto de VendIA.
  final double quantity;

  /// Precio unitario en COP.
  final double unitPrice;

  /// Descuento absoluto aplicado a esta línea (en COP). 0 si no hay.
  final double discount;

  /// Subtotal de la línea tal como lo devolvió el servidor.
  /// `(quantity * unitPrice) - discount`. En líneas creadas localmente
  /// (aún sin guardar) se inicializa con [computedSubtotal].
  final double subtotal;

  /// Orden de la línea dentro de la cotización.
  final int sortOrder;

  const QuoteItem({
    this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
    double? subtotal,
    this.sortOrder = 0,
  }) : subtotal = subtotal ?? (quantity * unitPrice - discount);

  /// True cuando la línea es un producto del inventario (no libre).
  bool get isInventoryItem => productId != null && productId!.isNotEmpty;

  /// Subtotal calculado localmente — fuente de verdad mientras el
  /// formulario aún no guardó la cotización.
  double get computedSubtotal {
    final raw = quantity * unitPrice - discount;
    return raw < 0 ? 0 : raw;
  }

  factory QuoteItem.fromJson(Map<String, dynamic> json) {
    final pid = json['product_id'];
    return QuoteItem(
      productId: (pid == null || pid == '') ? null : pid.toString(),
      name: (json['name'] as String?) ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      unitPrice: (json['unit_price'] as num? ?? 0).toDouble(),
      discount: (json['discount'] as num? ?? 0).toDouble(),
      subtotal: (json['subtotal'] as num?)?.toDouble(),
      sortOrder: (json['sort_order'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (productId != null && productId!.isNotEmpty)
          'product_id': productId,
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'discount': discount,
        'subtotal': computedSubtotal,
        'sort_order': sortOrder,
      };

  QuoteItem copyWith({
    String? productId,
    bool clearProductId = false,
    String? name,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? subtotal,
    int? sortOrder,
  }) {
    return QuoteItem(
      productId: clearProductId ? null : (productId ?? this.productId),
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      subtotal: subtotal,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
