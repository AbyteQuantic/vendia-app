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
  });

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
