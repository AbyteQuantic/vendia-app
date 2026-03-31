import 'package:isar/isar.dart';

part 'local_catalog_product.g.dart';

/// Cached products from the Open Food Facts catalog.
/// Synced from the backend on app start for offline-first autocomplete.
@collection
class LocalCatalogProduct {
  Id isarId = Isar.autoIncrement;

  @Index()
  late String name;

  late String brand;
  String? imageUrl;

  late DateTime syncedAt;

  static LocalCatalogProduct fromJson(Map<String, dynamic> json) {
    return LocalCatalogProduct()
      ..name = json['name'] as String? ?? ''
      ..brand = json['brand'] as String? ?? ''
      ..imageUrl = json['image_url'] as String?
      ..syncedAt = DateTime.now();
  }
}
