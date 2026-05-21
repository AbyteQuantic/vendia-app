// Spec: specs/029-precios-multi-tier/spec.md
class Product {
  final int id;
  final String uuid;
  final String name;
  final double price;
  final int stock;
  final String? imageUrl;
  final bool isAvailable;
  final bool requiresContainer;
  final int containerPrice;
  final String? barcode;
  final String? presentation;
  final String? content;

  /// F029: precios opcionales por tier (depósito contado / crédito /
  /// cliente final, o los nombres custom del tenant). Cuando es null
  /// el POS hace fallback al [price] retail con nota visual.
  final double? priceTier1;
  final double? priceTier2;
  final double? priceTier3;

  const Product({
    required this.id,
    this.uuid = '',
    required this.name,
    required this.price,
    required this.stock,
    this.imageUrl,
    this.isAvailable = true,
    this.requiresContainer = false,
    this.containerPrice = 0,
    this.barcode,
    this.presentation,
    this.content,
    this.priceTier1,
    this.priceTier2,
    this.priceTier3,
  });

  /// F029: precio efectivo para un tier dado. `'retail'` (default y fallback)
  /// devuelve el [price]; cualquier `tier_N` cuyo valor sea null cae al
  /// retail automáticamente — el caller decide si mostrar la nota visual
  /// usando [hasPriceForTier].
  double priceForTier(String tier) {
    switch (tier) {
      case 'tier_1':
        return priceTier1 ?? price;
      case 'tier_2':
        return priceTier2 ?? price;
      case 'tier_3':
        return priceTier3 ?? price;
      case 'retail':
      default:
        return price;
    }
  }

  /// F029: true si el producto tiene un precio configurado para el tier
  /// (no es null). `'retail'` siempre devuelve true porque el [price]
  /// es obligatorio. Sirve para que la UI sepa cuándo mostrar "⚠ usando
  /// precio retail" al lado de un item del carrito.
  bool hasPriceForTier(String tier) {
    switch (tier) {
      case 'tier_1':
        return priceTier1 != null;
      case 'tier_2':
        return priceTier2 != null;
      case 'tier_3':
        return priceTier3 != null;
      case 'retail':
      default:
        return true;
    }
  }

  /// Short subtitle: "Botella · 350ml"
  String get subtitle {
    final parts = <String>[
      if (presentation != null && presentation!.isNotEmpty) presentation!,
      if (content != null && content!.isNotEmpty) content!,
    ];
    return parts.join(' · ');
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    return Product(
      id: id is int ? id : 0,
      uuid: id is String ? id : (json['uuid'] as String? ?? id?.toString() ?? ''),
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      stock: json['stock'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      requiresContainer: json['requires_container'] as bool? ?? false,
      containerPrice: json['container_price'] as int? ?? 0,
      barcode: json['barcode'] as String?,
      presentation: json['presentation'] as String?,
      content: json['content'] as String?,
      // F029: tier prices opcionales (nullable). Tenants pre-migración
      // o productos sin tier configurado entregan null aquí.
      priceTier1: (json['price_tier_1'] as num?)?.toDouble(),
      priceTier2: (json['price_tier_2'] as num?)?.toDouble(),
      priceTier3: (json['price_tier_3'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'name': name,
        'price': price,
        'stock': stock,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'requires_container': requiresContainer,
        'container_price': containerPrice,
        'barcode': barcode,
        'presentation': presentation,
        'content': content,
        // F029: serializamos los tiers solo cuando hay valor para no
        // sobreescribir un campo en el backend con null por accidente.
        if (priceTier1 != null) 'price_tier_1': priceTier1,
        if (priceTier2 != null) 'price_tier_2': priceTier2,
        if (priceTier3 != null) 'price_tier_3': priceTier3,
      };

  String get formattedPrice {
    final int cents = price.round();
    final String s = cents.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }
}
