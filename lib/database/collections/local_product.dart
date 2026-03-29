import 'package:isar/isar.dart';

part 'local_product.g.dart';

@collection
class LocalProduct {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late String name;
  late double price;
  late int stock;
  String? imageUrl;
  late bool isAvailable;
  late bool requiresContainer;
  late int containerPrice;
  String? barcode;

  late DateTime clientUpdatedAt;
  int? serverId;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'price': price,
        'stock': stock,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'requires_container': requiresContainer,
        'container_price': containerPrice,
        'barcode': barcode,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalProduct fromJson(Map<String, dynamic> json) {
    return LocalProduct()
      ..uuid = json['uuid'] as String? ?? json['id']?.toString() ?? ''
      ..name = json['name'] as String
      ..price = (json['price'] as num).toDouble()
      ..stock = json['stock'] as int? ?? 0
      ..imageUrl = json['image_url'] as String?
      ..isAvailable = json['is_available'] as bool? ?? true
      ..requiresContainer = json['requires_container'] as bool? ?? false
      ..containerPrice = json['container_price'] as int? ?? 0
      ..barcode = json['barcode'] as String?
      ..serverId = json['id'] as int?
      ..clientUpdatedAt = json['client_updated_at'] != null
          ? DateTime.parse(json['client_updated_at'] as String)
          : DateTime.now();
  }
}
