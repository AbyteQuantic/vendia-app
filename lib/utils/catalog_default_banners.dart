// Spec: specs/082-catalogo-online-personalizacion/spec.md
//
// Banner POR DEFECTO del catálogo según el tipo de negocio. Espeja
// `admin-web/src/lib/catalog-fallbacks.ts` (la fuente que el catálogo público
// usa cuando el tendero no ha puesto una portada propia). Si cambian allá,
// actualizar aquí. Sirve para que el formulario muestre la MISMA imagen que se
// ve en la tienda en línea y no diga "sin portada" cuando sí hay una por defecto.
const Map<String, String> _defaultBannerByType = {
  'tienda_barrio':
      'https://images.unsplash.com/photo-1534723452862-4c874018d66d?q=80&w=1200&auto=format&fit=crop',
  'minimercado':
      'https://images.unsplash.com/photo-1542838132-92c53300491e?q=80&w=1200&auto=format&fit=crop',
  'restaurante':
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?q=80&w=1200&auto=format&fit=crop',
  'comidas_rapidas':
      'https://images.unsplash.com/photo-1561758033-d89a9ad46330?q=80&w=1200&auto=format&fit=crop',
  'bar':
      'https://images.unsplash.com/photo-1514362545857-3bc16c4c7d1b?q=80&w=1200&auto=format&fit=crop',
  'deposito_construccion':
      'https://images.unsplash.com/photo-1504148454959-57a6b91bd2e0?q=80&w=1200&auto=format&fit=crop',
  'manufactura':
      'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?q=80&w=1200&auto=format&fit=crop',
  'reparacion_muebles':
      'https://images.unsplash.com/photo-1530133532239-eda0f519f043?q=80&w=1200&auto=format&fit=crop',
  'emprendimiento_general':
      'https://images.unsplash.com/photo-1472851294608-062f824d29cc?q=80&w=1200&auto=format&fit=crop',
};

const String _globalFallbackBanner =
    'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?q=80&w=1200&auto=format&fit=crop';

/// Banner por defecto que el catálogo público mostraría para [businessType]
/// cuando la tienda no tiene portada propia.
String catalogDefaultBanner(String? businessType) {
  if (businessType == null) return _globalFallbackBanner;
  return _defaultBannerByType[businessType] ?? _globalFallbackBanner;
}
