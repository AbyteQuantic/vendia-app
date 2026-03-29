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
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int? ?? 0,
      uuid: json['uuid'] as String? ?? json['id']?.toString() ?? '',
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      stock: json['stock'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      requiresContainer: json['requires_container'] as bool? ?? false,
      containerPrice: json['container_price'] as int? ?? 0,
      barcode: json['barcode'] as String?,
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
