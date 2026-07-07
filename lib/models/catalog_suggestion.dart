// Spec: specs/097-completar-fotos-inventario/spec.md
import 'package:flutter/foundation.dart';

/// Sugerencia de foto del catálogo para un producto sin imagen, resuelta por
/// código de barras (Spec 096/097). [verified] = la confirmaron 2+ tiendas;
/// si es false es un respaldo (Open Food Facts) que el tendero puede aceptar
/// o rechazar. Value object inmutable, fromJson defensivo (nunca lanza).
@immutable
class CatalogSuggestion {
  final String imageUrl;
  final String name;
  final String brand;
  final bool verified;

  const CatalogSuggestion({
    required this.imageUrl,
    this.name = '',
    this.brand = '',
    this.verified = false,
  });

  static CatalogSuggestion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = (raw['image_url'] ?? '').toString().trim();
    if (url.isEmpty) return null; // sin imagen no es una sugerencia
    return CatalogSuggestion(
      imageUrl: url,
      name: (raw['name'] ?? '').toString(),
      brand: (raw['brand'] ?? '').toString(),
      verified: raw['verified'] == true,
    );
  }
}
