// Spec: specs/090-lazyload-imagenes/spec.md
//
// Reescritura de URL para servir MINIATURAS redimensionadas desde Supabase
// Storage (transformación de imágenes on-the-fly), en vez del PNG original.
//
// Medición real: una foto de producto de 839 KB (PNG original) servida para
// una miniatura de 56dp pesa 78 KB vía `render/image?width=200&quality=70`
// (≈10.7× menos bytes). Solo cambiamos cómo el cliente PIDE la imagen; la
// foto original en Storage queda intacta como fuente.
//
// SOLO aplica a NUESTRO Supabase Storage público
// (`/storage/v1/object/public/…`). Las fotos externas (OpenFoodFacts, VTEX,
// otros hosts) y las de R2 no pasan por el transformador de Supabase → se
// dejan tal cual. Las URLs ya transformadas (`/render/image/`) tampoco se
// tocan (evita doble reescritura).
library supabase_image;

/// Ruta del endpoint de objeto público de Supabase Storage.
const String _kObjectPublicPath = '/storage/v1/object/public/';

/// Ruta del endpoint de transformación de imágenes de Supabase.
const String _kRenderImagePath = '/storage/v1/render/image/public/';

/// Calidad por defecto de la miniatura (0-100). 70 da el ~10× de ahorro sin
/// degradar visiblemente una foto de producto pequeña.
const int kDefaultThumbQuality = 70;

/// Factor de densidad de píxeles asumido. Cubre pantallas de gama alta (×3)
/// para que la miniatura se vea nítida sin pedir el original completo.
const double kAssumedDpr = 3.0;

/// Escalones de ancho en píxeles. Redondear a estos valores maximiza los
/// aciertos de caché (CDN + navegador): pocas variantes por foto en vez de
/// una distinta por cada dp de render.
const List<int> kThumbWidthSteps = [100, 200, 400, 800];

/// Redondea [pixels] al siguiente escalón de [kThumbWidthSteps] (hacia arriba)
/// para no pedir una imagen más pequeña que el render. Sobre el máximo escalón
/// se queda en el máximo (800) — más que eso es prácticamente el original.
int snapThumbWidth(double pixels) {
  final px = pixels.ceil();
  for (final step in kThumbWidthSteps) {
    if (px <= step) return step;
  }
  return kThumbWidthSteps.last;
}

/// Deriva el ancho objetivo en píxeles a partir del tamaño de render lógico
/// del widget. Usa la mayor dimensión FINITA (width/height) × DPR asumido.
/// Devuelve `null` si no hay ninguna dimensión finita útil (p.ej. ambas son
/// `null`/`infinity`) — en ese caso no se puede dimensionar la miniatura.
int? targetThumbWidth(double? width, double? height, {double dpr = kAssumedDpr}) {
  double logical = 0;
  if (width != null && width.isFinite && width > 0) {
    logical = width;
  }
  if (height != null && height.isFinite && height > 0 && height > logical) {
    logical = height;
  }
  if (logical <= 0) return null;
  return snapThumbWidth(logical * dpr);
}

/// `true` si [url] apunta a nuestro Supabase Storage público y todavía NO está
/// transformada. Solo estas URLs se pueden reescribir a `render/image`.
bool isTransformableSupabaseUrl(String url) {
  if (url.isEmpty) return false;
  if (url.contains(_kRenderImagePath)) return false; // ya transformada
  return url.contains(_kObjectPublicPath);
}

/// Devuelve [url] reescrita para servir una miniatura de [targetWidth] px de
/// ancho vía el transformador de Supabase. Si [url] no es transformable
/// (externa, R2, ya-render, vacía) o [targetWidth] es `null`, la devuelve
/// SIN CAMBIOS.
String supabaseThumbUrl(
  String url, {
  required int? targetWidth,
  int quality = kDefaultThumbQuality,
}) {
  if (targetWidth == null || !isTransformableSupabaseUrl(url)) return url;

  final transformed = url.replaceFirst(_kObjectPublicPath, _kRenderImagePath);
  final sep = transformed.contains('?') ? '&' : '?';
  return '$transformed${sep}width=$targetWidth&quality=$quality&resize=cover';
}

/// Atajo de alto nivel para widgets: reescribe [url] a una miniatura del
/// tamaño de render (deriva el ancho de [width]/[height]). URLs no
/// transformables o sin dimensión útil se devuelven intactas.
String optimizedProductImageUrl(
  String? url, {
  double? width,
  double? height,
  int quality = kDefaultThumbQuality,
}) {
  if (url == null || url.isEmpty) return url ?? '';
  return supabaseThumbUrl(
    url,
    targetWidth: targetThumbWidth(width, height),
    quality: quality,
  );
}
