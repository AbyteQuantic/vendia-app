// Spec: specs/033-difusion-promociones/spec.md
//
// Parser de plantillas de mensaje para la difusión de promociones (F033).
//
// El dueño escribe un texto base que puede usar los placeholders
// `{nombre}` y `{primer_nombre}`. Antes de empezar la cola de envío,
// VendIA pre-genera TODOS los mensajes personalizados — el dueño ya no
// edita nada en la cola (spec §4.5, mejora 2).
//
// Sustitución defensiva (spec §4.5):
//   - `{nombre}`         → nombre completo del cliente.
//   - `{primer_nombre}`  → primera palabra del nombre.
//   - Si el cliente no tiene nombre, NO queda un texto roto: el saludo
//     cae a "Hola 👋" sin nombre. El parser detecta el patrón de saludo
//     "Hola {placeholder}" y lo colapsa a "Hola 👋" para que no quede
//     un "Hola ," ni un doble espacio.
//   - Cualquier placeholder suelto (sin saludo) se sustituye por cadena
//     vacía y se limpian los espacios sobrantes.
//
// El parser no lanza nunca: ante cualquier entrada produce un texto
// utilizable.

/// Placeholders soportados en una plantilla de mensaje de promoción.
class PromotionPlaceholders {
  static const String fullName = '{nombre}';
  static const String firstName = '{primer_nombre}';

  /// Emoji de saludo que reemplaza al placeholder cuando el cliente no
  /// tiene nombre — el saludo "Hola {nombre}" colapsa a "Hola 👋"
  /// preservando la mayúscula/minúscula original de "Hola".
  static const String greetingFallback = 'Hola 👋';

  const PromotionPlaceholders._();
}

/// Renderiza una [template] sustituyendo los placeholders con el
/// [customerName] del cliente.
///
/// Devuelve siempre un texto utilizable — nunca lanza. Las reglas:
///
///  * `{nombre}` → nombre completo (trim).
///  * `{primer_nombre}` → primera palabra del nombre.
///  * Sin nombre → el saludo "Hola {placeholder}" se colapsa a
///    "Hola 👋"; los placeholders sueltos quedan vacíos y se limpian
///    los espacios resultantes.
String renderPromotionMessage({
  required String template,
  required String customerName,
}) {
  final base = template;
  final name = customerName.trim();
  final firstName = _firstWord(name);

  if (name.isEmpty) {
    return _renderWithoutName(base);
  }

  // Con nombre: sustitución directa de ambos placeholders.
  var result = base
      .replaceAll(PromotionPlaceholders.fullName, name)
      .replaceAll(PromotionPlaceholders.firstName, firstName);
  return _collapseWhitespace(result);
}

/// Cliente sin nombre: el saludo "Hola {placeholder}" colapsa a
/// "Hola 👋" y cualquier placeholder restante se vacía.
String _renderWithoutName(String template) {
  // Colapsa "Hola {nombre}" / "hola  {primer_nombre}" → "Hola 👋".
  // El patrón es case-insensitive y tolera espacios extra; se preserva
  // la mayúscula/minúscula original de "Hola" para no alterar el tono
  // del mensaje del dueño.
  final greeting = RegExp(
    r'(hola)\s*(\{nombre\}|\{primer_nombre\})',
    caseSensitive: false,
  );
  var result = template.replaceAllMapped(
    greeting,
    (m) => '${m.group(1)} 👋',
  );

  // Cualquier placeholder suelto que no formaba parte de un saludo
  // queda como cadena vacía.
  result = result
      .replaceAll(PromotionPlaceholders.fullName, '')
      .replaceAll(PromotionPlaceholders.firstName, '');

  return _collapseWhitespace(result);
}

/// Primera palabra de un nombre — `'María José Pérez'` → `'María'`.
/// Para un nombre vacío devuelve cadena vacía.
String _firstWord(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'\s+'));
  return parts.first;
}

/// Limpia los espacios sobrantes que deja una sustitución vacía:
/// colapsa runs de espacios/tabs a uno solo y recorta espacio antes de
/// signos de puntuación comunes. No toca los saltos de línea.
String _collapseWhitespace(String text) {
  var result = text;
  // Colapsa espacios/tabs múltiples (no newlines) a uno.
  result = result.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  // Quita el espacio antes de , . ; : ! ? que queda al vaciar un
  // placeholder ("Hola , ..." → "Hola, ...").
  result = result.replaceAllMapped(
    RegExp(r' +([,.;:!?])'),
    (m) => m.group(1)!,
  );
  // Recorta espacios al inicio/fin de cada línea.
  result = result
      .split('\n')
      .map((line) => line.trim())
      .join('\n');
  return result.trim();
}
