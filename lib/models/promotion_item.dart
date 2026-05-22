// Spec: specs/033-difusion-promociones/spec.md
//
// Modelo inmutable de un item en oferta dentro de una promoción de
// difusión (F033).
//
// Un [PromotionItem] vincula un producto del inventario a una promoción
// y le asigna un precio promocional. El descuento se expresa de UNA de
// dos formas (plan §3):
//   - [promoPrice]  → precio fijo en COP (ej. $4.000).
//   - [discountPct] → porcentaje de descuento (ej. 20.0 = 20%).
// Exactamente uno de los dos viaja no-nulo; el otro queda en null.

/// Forma en que se expresa el descuento de un item en oferta.
enum PromotionDiscountMode {
  /// Precio fijo en COP — usa [PromotionItem.promoPrice].
  fixedPrice,

  /// Porcentaje de descuento — usa [PromotionItem.discountPct].
  percentage,
}

/// Un producto en oferta dentro de una promoción.
class PromotionItem {
  /// UUID del registro de item. Vacío cuando el item aún no se guardó.
  final String id;

  /// UUID del producto del inventario.
  final String productId;

  /// Nombre del producto — denormalizado para pintar la línea sin un
  /// fetch extra.
  final String productName;

  /// Precio original del producto (COP) — para mostrar el "antes".
  final double originalPrice;

  /// Precio promocional fijo (COP). Null cuando aplica [discountPct].
  final double? promoPrice;

  /// Porcentaje de descuento (0-100). Null cuando aplica [promoPrice].
  final double? discountPct;

  const PromotionItem({
    this.id = '',
    required this.productId,
    this.productName = '',
    this.originalPrice = 0,
    this.promoPrice,
    this.discountPct,
  });

  /// Modo de descuento de este item.
  PromotionDiscountMode get mode => discountPct != null
      ? PromotionDiscountMode.percentage
      : PromotionDiscountMode.fixedPrice;

  /// Precio final que paga el cliente con la promoción aplicada.
  ///
  /// Con [promoPrice] devuelve ese valor; con [discountPct] lo calcula
  /// sobre [originalPrice]. Defensivo: nunca devuelve negativo.
  double get effectivePrice {
    if (promoPrice != null) {
      return promoPrice! < 0 ? 0 : promoPrice!;
    }
    if (discountPct != null) {
      final pct = discountPct!.clamp(0, 100).toDouble();
      final result = originalPrice * (1 - pct / 100);
      return result < 0 ? 0 : result;
    }
    return originalPrice;
  }

  factory PromotionItem.fromJson(Map<String, dynamic> json) {
    return PromotionItem(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      productId: (json['product_id'] ?? json['product_uuid'] ?? '')
          .toString(),
      productName: (json['product_name'] as String?) ?? '',
      originalPrice: (json['original_price'] as num? ?? 0).toDouble(),
      promoPrice: (json['promo_price'] as num?)?.toDouble(),
      discountPct: (json['discount_pct'] as num?)?.toDouble(),
    );
  }

  /// Payload para POST/PATCH de la promoción — solo viaja el campo del
  /// modo activo (plan §4: exactamente uno no-nulo).
  Map<String, dynamic> toJson() => {
        'product_id': productId,
        if (promoPrice != null) 'promo_price': promoPrice,
        if (discountPct != null) 'discount_pct': discountPct,
      };

  PromotionItem copyWith({
    String? id,
    String? productId,
    String? productName,
    double? originalPrice,
    double? promoPrice,
    double? discountPct,
    bool clearPromoPrice = false,
    bool clearDiscountPct = false,
  }) {
    return PromotionItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      originalPrice: originalPrice ?? this.originalPrice,
      promoPrice: clearPromoPrice ? null : (promoPrice ?? this.promoPrice),
      discountPct:
          clearDiscountPct ? null : (discountPct ?? this.discountPct),
    );
  }
}
