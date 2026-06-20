// Spec: specs/047-offline-sync-contract/spec.md (fix: reservedStock late trap)
//
// Construcción centralizada de un LocalProduct para GUARDAR (creación manual /
// importación). Existe porque `LocalProduct.reservedStock` es `late int` SIN
// default: si se construye el objeto sin asignarlo, Isar lanza
// `LateInitializationError` al serializarlo en `put()` (y `toJson()` también lo
// lee). Ese bug estaba latente —online el producto se creaba en el servidor y
// volvía por el sync (que sí setea reserved_stock)— y solo se destapó al
// guardar OFFLINE, donde no hay round-trip que lo enmascare. Centralizar evita
// que cada call-site olvide el campo.

import 'collections/local_product.dart';

LocalProduct buildSavedLocalProduct({
  required String uuid,
  required String name,
  required double price,
  required int stock,
  int minStock = 0,
  String? imageUrl,
  String barcode = '',
  String? presentation,
  String content = '',
  DateTime? expiryDate,
  bool isAvailable = true,
  bool requiresContainer = false,
  int containerPrice = 0,
  DateTime? clientUpdatedAt,
  // Spec 068 — categoría + características (opcionales, aditivos).
  String? category,
  String? characteristics,
}) {
  return LocalProduct()
    ..uuid = uuid
    ..name = name
    ..price = price
    ..stock = stock
    ..reservedStock = 0 // campo `late` que faltaba en los call-sites
    ..minStock = minStock
    ..imageUrl = imageUrl
    ..isAvailable = isAvailable
    ..requiresContainer = requiresContainer
    ..containerPrice = containerPrice
    ..barcode = barcode
    ..presentation = presentation
    ..content = content
    ..category = category
    ..characteristics = characteristics
    ..expiryDate = expiryDate
    ..clientUpdatedAt = clientUpdatedAt ?? DateTime.now();
}
