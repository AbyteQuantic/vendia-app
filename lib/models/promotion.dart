/// Promotion model for VendIA POS system.
/// Manages product discounts, 2x1 offers, and AI-suggested promotions.
class Promotion {
  final String uuid;
  final String productUuid;
  final String productName;
  final double originalPrice;
  final double offerPrice;
  final PromotionType type;
  final String? reason; // "Vence en 3 días", "Baja rotación"
  final bool isActive;
  final bool isSuggestedByAI;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final int? serverId;

  Promotion({
    required this.uuid,
    required this.productUuid,
    required this.productName,
    required this.originalPrice,
    required this.offerPrice,
    this.type = PromotionType.descuento,
    this.reason,
    this.isActive = true,
    this.isSuggestedByAI = false,
    this.expiresAt,
    DateTime? createdAt,
    this.serverId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Discount amount in COP
  double get discountAmount => originalPrice - offerPrice;

  /// Discount percentage
  double get discountPercent =>
      originalPrice > 0 ? (discountAmount / originalPrice) * 100 : 0;

  /// Display label for promotion type
  String get typeLabel {
    switch (type) {
      case PromotionType.descuento:
        return 'Descuento';
      case PromotionType.dosXuno:
        return '2×1';
      case PromotionType.combo:
        return 'Combo';
    }
  }

  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      uuid: json['uuid'] as String,
      productUuid: json['product_uuid'] as String,
      productName: json['product_name'] as String,
      originalPrice: (json['original_price'] as num).toDouble(),
      offerPrice: (json['offer_price'] as num).toDouble(),
      type: PromotionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PromotionType.descuento,
      ),
      reason: json['reason'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isSuggestedByAI: json['is_suggested_by_ai'] as bool? ?? false,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      serverId: json['id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'product_uuid': productUuid,
        'product_name': productName,
        'original_price': originalPrice,
        'offer_price': offerPrice,
        'type': type.name,
        'reason': reason,
        'is_active': isActive,
        'is_suggested_by_ai': isSuggestedByAI,
        'expires_at': expiresAt?.toIso8601String(),
      };
}

enum PromotionType { descuento, dosXuno, combo }
