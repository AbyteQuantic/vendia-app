// Spec: specs/083-mesas-catalogo-qr/spec.md
//
// Normalización de texto libre categórico (áreas, categorías) para REDUCIR
// duplicados por tildes, mayúsculas, espacios o typos de espaciado. Dos piezas:
//   · foldKey: clave de COMPARACIÓN (nunca se guarda) — sin tildes, minúsculas,
//     espacios colapsados.
//   · canonicalValue: al guardar, si lo escrito equivale a un valor existente,
//     reutiliza la grafía existente; si no, deja lo escrito (trim).

/// Clave canónica para comparar dos valores e ignorar tildes/mayúsculas/espacios.
String foldKey(String s) {
  final t = s.trim().toLowerCase();
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in t.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Devuelve la grafía CANÓNICA de [typed]: si ya existe un valor equivalente en
/// [existing] (por [foldKey]), reutiliza ESE; si no, devuelve [typed] sin
/// espacios sobrantes. Evita "Gaseosas"/"gaseosas"/"  Gaseosas " como distintos.
String canonicalValue(String typed, Iterable<String> existing) {
  final k = foldKey(typed);
  if (k.isEmpty) return '';
  for (final e in existing) {
    if (foldKey(e) == k) return e.trim();
  }
  return typed.trim();
}
