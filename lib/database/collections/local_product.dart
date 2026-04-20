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

  /// Expiration date (YYYY-MM-DD resolution). Nullable because non-perishable
  /// SKUs (cleaning supplies, stationery, liquor) never carry an expiration.
  @Index()
  DateTime? expiryDate;

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
        // ISO-8601 date (YYYY-MM-DD). Backend column is DATE, so we strip
        // the time component to avoid day-boundary surprises near midnight.
        'expiry_date': expiryDate == null
            ? null
            : '${expiryDate!.year.toString().padLeft(4, '0')}-'
                '${expiryDate!.month.toString().padLeft(2, '0')}-'
                '${expiryDate!.day.toString().padLeft(2, '0')}',
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalProduct fromJson(Map<String, dynamic> json) {
    // Backend sends "id" as UUID string; use photo_url if available
    final id = json['id'];
    final uuid = id is String ? id : (json['uuid'] as String? ?? id?.toString() ?? '');
    final photoUrl = json['photo_url'] as String?;
    final imageUrl = json['image_url'] as String?;
    final bestImage = (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : imageUrl;

    DateTime? parsedExpiry;
    final rawExpiry = json['expiry_date'];
    if (rawExpiry is String && rawExpiry.isNotEmpty) {
      parsedExpiry = DateTime.tryParse(rawExpiry);
    }

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
      ..expiryDate = parsedExpiry
      ..clientUpdatedAt = json['client_updated_at'] != null
          ? DateTime.parse(json['client_updated_at'] as String)
          : DateTime.now();
  }
}
