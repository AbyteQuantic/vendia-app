// Spec: specs/026-importador-clientes/spec.md

/// Resultado de validar una fila mapeada.
class ValidationResult {
  final bool ok;
  final String? reason;

  const ValidationResult.ok() : ok = true, reason = null;
  const ValidationResult.fail(this.reason) : ok = false;
}

/// Columnas exportables del modelo Customer.
/// Columnas internas (tenant_id, terms_accepted, etc.) no aparecen aquí.
const List<String> kExportableTargets = ['name', 'phone', 'email', 'notes'];

/// Tabla de sinónimos: target → lista de sinónimos reconocidos.
/// Se usa para el auto-mapeo de headers de un archivo importado.
const Map<String, List<String>> _kSynonyms = {
  'name': [
    'nombre',
    'nombres',
    'cliente',
    'nombre del cliente',
    'name',
    'full name',
    'razon social',
    'razón social',
  ],
  'phone': [
    'telefono',
    'teléfono',
    'celular',
    'cel',
    'phone',
    'movil',
    'móvil',
    'whatsapp',
    'número',
    'numero',
    'tel',
  ],
  'email': [
    'email',
    'correo',
    'correo electrónico',
    'correo electronico',
    'mail',
    'e-mail',
  ],
  'notes': [
    'notas',
    'observaciones',
    'comentarios',
    'nota',
    'obs',
    'comentario',
  ],
};

/// Helper de normalización Unicode → ASCII básico.
/// Reemplaza vocales con tilde, diéresis y ñ; case-insensitive.
String _normalize(String s) {
  // Map individual accented characters to their ASCII equivalents.
  // Both lower and upper variants are listed.
  const _map = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n',
    'Á': 'a', 'À': 'a', 'Ä': 'a', 'Â': 'a', 'Ã': 'a',
    'É': 'e', 'È': 'e', 'Ë': 'e', 'Ê': 'e',
    'Í': 'i', 'Ì': 'i', 'Ï': 'i', 'Î': 'i',
    'Ó': 'o', 'Ò': 'o', 'Ö': 'o', 'Ô': 'o', 'Õ': 'o',
    'Ú': 'u', 'Ù': 'u', 'Ü': 'u', 'Û': 'u',
    'Ñ': 'n',
  };
  final buf = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    buf.write(_map[c] ?? c);
  }
  return buf.toString().toLowerCase().trim();
}

/// Servicio de mapeo e importación de clientes.
class CustomerImportMapper {
  CustomerImportMapper._();

  /// Normaliza un header para comparación.
  /// Expuesto para tests.
  static String normalizeHeader(String h) => _normalize(h.trim());

  /// Propone un mapeo automático dado una lista de headers del archivo.
  ///
  /// Devuelve `Map<int, String?>` donde la clave es el índice del header y
  /// el valor es el target column ('name', 'phone', 'email', 'notes') o
  /// `null` si el header no se reconoce.
  ///
  /// Regla: si dos headers mapean al mismo target, el primero gana y el
  /// segundo queda como `null`.
  static Map<int, String?> proposeMapping(List<String> headers) {
    final result = <int, String?>{};
    final claimed = <String>{};

    // Pre-compute normalized synonyms → target
    final synonymIndex = <String, String>{};
    for (final entry in _kSynonyms.entries) {
      for (final syn in entry.value) {
        synonymIndex[_normalize(syn)] = entry.key;
      }
    }

    for (var i = 0; i < headers.length; i++) {
      final normalized = _normalize(headers[i]);
      final target = synonymIndex[normalized];
      if (target != null && !claimed.contains(target)) {
        result[i] = target;
        claimed.add(target);
      } else {
        result[i] = null;
      }
    }

    return result;
  }

  /// Valida una fila ya mapeada (map de targetColumn → valor).
  ///
  /// Reglas:
  ///   - `name` no vacío y mínimo 2 caracteres después de trim.
  ///   - Los demás campos no se validan estrictamente (FR-04).
  static ValidationResult validateRow(Map<String, dynamic> row) {
    final rawName = row['name'];
    final name = (rawName as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) {
      return const ValidationResult.fail('nombre vacío');
    }
    if (name.length < 2) {
      return const ValidationResult.fail('nombre muy corto (mínimo 2 caracteres)');
    }
    return const ValidationResult.ok();
  }

  /// Aplica el mapeo a una fila raw (de headers a valores).
  ///
  /// [rawRow] es una lista de valores en el mismo orden que los headers.
  /// [mapping] es el resultado de [proposeMapping].
  ///
  /// Devuelve un mapa `{targetColumn: valor}` con solo las columnas
  /// mapeadas y no nulas.
  static Map<String, dynamic> applyMapping(
    List<dynamic> rawRow,
    Map<int, String?> mapping,
  ) {
    final result = <String, dynamic>{};
    for (var i = 0; i < rawRow.length && i < mapping.length + rawRow.length; i++) {
      final target = mapping[i];
      if (target != null) {
        final raw = rawRow.length > i ? rawRow[i] : null;
        final value = raw?.toString().trim() ?? '';
        result[target] = value;
      }
    }
    return result;
  }
}
