import 'dart:convert';
import 'product.dart';

class CartItem {
  final Product product;
  int quantity;

  /// When true the line is an ad-hoc service charge (no inventory row).
  /// `product` is a synthetic placeholder carrying the display name so
  /// the cart UI doesn't need to branch. The sale payload reads
  /// [customDescription] / [customUnitPrice] directly instead.
  final bool isService;
  final String? customDescription;
  final double? customUnitPrice;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.isService = false,
    this.customDescription,
    this.customUnitPrice,
  });

  double get subtotal => product.price * quantity;

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        if (isService) 'is_service': true,
        if (customDescription != null) 'custom_description': customDescription,
        if (customUnitPrice != null) 'custom_unit_price': customUnitPrice,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(json['product'] as Map<String, dynamic>),
        quantity: json['quantity'] as int? ?? 1,
        isService: json['is_service'] == true,
        customDescription: json['custom_description'] as String?,
        customUnitPrice: (json['custom_unit_price'] as num?)?.toDouble(),
      );

  static String encodeList(List<CartItem> items) =>
      jsonEncode(items.map((i) => i.toJson()).toList());

  static List<CartItem> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String get formattedSubtotal {
    final int cents = subtotal.round();
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
