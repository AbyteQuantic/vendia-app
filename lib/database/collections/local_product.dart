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
  String? presentation;
  String? content;

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
        'presentation': presentation,
        'content': content,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalProduct fromJson(Map<String, dynamic> json) {
    // Backend sends "id" as UUID string; use photo_url if available
    final id = json['id'];
    final uuid = id is String ? id : (json['uuid'] as String? ?? id?.toString() ?? '');
    final photoUrl = json['photo_url'] as String?;
    final imageUrl = json['image_url'] as String?;
    final bestImage = (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : imageUrl;

    return LocalProduct()
      ..uuid = uuid
      ..name = json['name'] as String
      ..price = (json['price'] as num).toDouble()
      ..stock = json['stock'] as int? ?? 0
      ..imageUrl = bestImage
      ..isAvailable = json['is_available'] as bool? ?? true
      ..requiresContainer = json['requires_container'] as bool? ?? false
      ..containerPrice = json['container_price'] as int? ?? 0
      ..barcode = json['barcode'] as String?
      ..presentation = json['presentation'] as String?
      ..content = json['content'] as String?
      ..clientUpdatedAt = json['client_updated_at'] != null
          ? DateTime.parse(json['client_updated_at'] as String)
          : DateTime.now();
  }
}
