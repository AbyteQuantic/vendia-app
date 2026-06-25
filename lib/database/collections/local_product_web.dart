// Modelo plano de producto para la build web (sin Isar).
//
// Espejo de `local_product_io.dart` sin las anotaciones `@collection`/`@Index`
// ni `Id`/`Isar`, porque el backend nativo de Isar no compila a web. En web
// estas instancias viven solo en memoria; no hay persistencia offline.
class LocalProduct {
  int isarId = 0;

  late String uuid;
  late String name;
  late double price;
  late int stock;
  late int reservedStock;

  /// Punto de reorden (Spec 050). Non-late + default 0 (igual que el io).
  int minStock = 0;
  String? imageUrl;
  late bool isAvailable;
  late bool requiresContainer;
  late int containerPrice;
  String? barcode;
  String? presentation;
  String? content;
  // Spec 068 — espejo del io: categoría + características (aditivos, nullable).
  String? category;
  String? characteristics;
  // Espejo del io (Spec 043/080): plato de menú + modo de venta para el badge.
  bool isMenuItem = false;
  String availabilityMode = 'a_demanda';
  DateTime? expiryDate;
  late DateTime clientUpdatedAt;
  int? serverId;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'price': price,
        'stock': stock,
        'reserved_stock': reservedStock,
        'min_stock': minStock,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'requires_container': requiresContainer,
        'container_price': containerPrice,
        'barcode': barcode,
        'presentation': presentation,
        'content': content,
        'category': category,
        'characteristics': characteristics,
        'is_menu_item': isMenuItem,
        'availability_mode': availabilityMode,
        'expiry_date': expiryDate == null
            ? null
            : '${expiryDate!.year.toString().padLeft(4, '0')}-'
                '${expiryDate!.month.toString().padLeft(2, '0')}-'
                '${expiryDate!.day.toString().padLeft(2, '0')}',
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalProduct fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final uuid =
        id is String ? id : (json['uuid'] as String? ?? id?.toString() ?? '');
    final photoUrl = json['photo_url'] as String?;
    final imageUrl = json['image_url'] as String?;
    final bestImage =
        (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : imageUrl;

    DateTime? parsedExpiry;
    final rawExpiry = json['expiry_date'];
    if (rawExpiry is String && rawExpiry.isNotEmpty) {
      parsedExpiry = DateTime.tryParse(rawExpiry);
    }

    return LocalProduct()
      ..uuid = uuid
      ..name = json['name'] as String? ?? ''
      ..price = (json['price'] as num?)?.toDouble() ?? 0
      ..stock = (json['stock'] as num?)?.toInt() ?? 0
      ..reservedStock = (json['reserved_stock'] as num?)?.toInt() ?? 0
      ..minStock = (json['min_stock'] as num?)?.toInt() ?? 0
      ..imageUrl = bestImage
      ..isAvailable = json['is_available'] as bool? ?? true
      ..requiresContainer = json['requires_container'] as bool? ?? false
      ..containerPrice = (json['container_price'] as num?)?.toInt() ?? 0
      ..barcode = json['barcode'] as String?
      ..presentation = json['presentation'] as String?
      ..content = json['content'] as String?
      ..category = json['category'] as String?
      ..characteristics = json['characteristics'] as String?
      ..isMenuItem = json['is_menu_item'] as bool? ?? false
      ..availabilityMode = (json['availability_mode'] as String?) ?? 'a_demanda'
      ..expiryDate = parsedExpiry
      ..clientUpdatedAt =
          DateTime.tryParse(json['client_updated_at'] as String? ?? '') ??
              DateTime.now();
  }

  int get availableStock {
    final v = stock - reservedStock;
    return v < 0 ? 0 : v;
  }
}
