// Spec: specs/042-modulo-eventos/spec.md
//
// Convierte el markdown de la descripción del evento al formato de WhatsApp
// para los mensajes de difusión: la negrita markdown (**texto**) pasa a la
// negrita de WhatsApp (*texto*), y los títulos (## Título) a una línea en
// negrita. Así el mensaje no muestra los asteriscos dobles ni los numerales.

/// Convierte markdown básico al estilo de WhatsApp.
String markdownToWhatsApp(String md) {
  var s = md;
  // Títulos "## X" / "# X" → "*X*" (negrita de WhatsApp).
  s = s.replaceAllMapped(
    RegExp(r'^\s{0,3}#{1,6}\s+(.+)$', multiLine: true),
    (m) => '*${m[1]!.trim()}*',
  );
  // Negrita markdown **X** → *X* (negrita de WhatsApp).
  s = s.replaceAll('**', '*');
  return s;
}
