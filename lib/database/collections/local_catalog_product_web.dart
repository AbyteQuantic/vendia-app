// Modelo plano del catálogo OFF para la build web (sin Isar).
// Espejo de `local_catalog_product_io.dart` sin anotaciones Isar.
class LocalCatalogProduct {
  int isarId = 0;

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
