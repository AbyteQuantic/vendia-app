// Spec: specs/086-branding-estacional/spec.md
//
// Mapa CLAVE de temporada → nombre del ícono nativo PRE-EMPAQUETADO. icon_variant
// del servidor selecciona uno de estos sets ya incluidos en el binario (Apple/
// Android no permiten ícono 100% remoto). 'default'/desconocido → ícono primario.

/// Nombre del ícono alterno nativo para [variant], o null para el primario.
/// Debe coincidir EXACTO con:
///   - iOS: la key en Info.plist CFBundleAlternateIcons.
///   - Android: el sufijo del activity-alias (.MainActivity<Variant>).
String? nativeIconName(String? variant) {
  switch (variant) {
    // Sets PRE-EMPAQUETADOS (íconos nativos listos para el switch):
    case 'navidad':
      return 'navidad';
    case 'mundial':
      return 'mundial';
    case 'dia_mujer':
      return 'dia_mujer';
    case 'dia_madre':
      return 'dia_madre';
    case 'dia_padre':
      return 'dia_padre';
    // Variantes válidas en config (colores/banner sí cambian) pero SIN ícono
    // pre-empaquetado todavía → caen al ícono primario hasta agregar su set:
    // amor_amistad, halloween, patrias, anio_nuevo.
    default:
      return null; // ícono primario VendIA
  }
}
