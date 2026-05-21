// Spec: specs/027-importador-inventario/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
//
// Mapper de importación de productos: propueMapping, validateRow,
// normalizePriceCOP y applyMapping.
// Espejo arquitectónico de customer_import_mapper.dart (F026).

/// Resultado de validar una fila mapeada.
class ValidationResult {
  final bool ok;
  final String? reason;

  const ValidationResult.ok() : ok = true, reason = null;
  const ValidationResult.fail(this.reason) : ok = false;
}

/// Columnas exportables del modelo Product (excluyendo las internas).
/// Las columnas internas (tenant_id, id, timestamps, ingestion_method,
/// price_status, is_ai_enhanced, photo_url, image_url, is_available,
/// branch_id, created_by, category_id, supplier_id, is_recipe, recipe_id,
/// requires_container, container_price) NO aparecen aquí (FR-05).
const List<String> kProductTargets = [
  'name',
  'price',
  'barcode',
  'purchase_price',
  'stock',
  'min_stock',
  'category',
  'emoji',
  'unit',
  'presentation',
  'content',
  'expiry_date',
  // F029: tiers opcionales — solo se aplican si el CSV los trae y
  // si el tenant tiene la capacidad enable_price_tiers ON. El backend
  // ignora valores cuando la capacidad está OFF, así que mapearlos
  // aquí nunca rompe la importación legacy.
  'price_tier_1',
  'price_tier_2',
  'price_tier_3',
];

/// Tabla de sinónimos según spec §8: target → lista de sinónimos.
const Map<String, List<String>> _kSynonyms = {
  'name': [
    'nombre',
    'producto',
    'nombre del producto',
    'item',
    'descripcion',
    'descripción',
    'name',
  ],
  'price': [
    'precio',
    'precio venta',
    'precio_venta',
    'valor',
    'price',
    'precio publico',
    'precio público',
    'publico',
    'pv',
  ],
  'barcode': [
    'codigo de barras',
    'código de barras',
    'barcode',
    'codigo',
    'código',
    'ean',
    'upc',
    'sku',
    'ref',
    'referencia',
  ],
  'purchase_price': [
    'precio compra',
    'precio_compra',
    'costo',
    'purchase price',
    'cost',
    'valor compra',
    'pc',
  ],
  'stock': [
    'stock',
    'inventario',
    'cantidad',
    'qty',
    'unidades',
    'existencias',
    'saldo',
  ],
  'min_stock': [
    'stock minimo',
    'stock mínimo',
    'min stock',
    'minimo',
    'alerta',
    'stock_minimo',
  ],
  'category': [
    'categoria',
    'categoría',
    'category',
    'tipo',
    'linea',
    'línea',
  ],
  'emoji': [
    'emoji',
    'icono',
    'ícono',
  ],
  'unit': [
    'unidad',
    'medida',
    'unit',
  ],
  'presentation': [
    'presentacion',
    'presentación',
    'presentation',
    'empaque',
  ],
  'content': [
    'contenido',
    'tamano',
    'content',
    'peso',
    'volumen',
  ],
  'expiry_date': [
    'vencimiento',
    'fecha vencimiento',
    'expira',
    'caduca',
    'expiry',
    'fecha de vencimiento',
  ],
  // F029 — sinónimos de tiers. Cobertura amplia: cualquier columna que
  // huela a "mayorista", "contado", "depósito" o "detal" cae a su tier
  // correspondiente. El dueño puede haber renombrado los tiers en su
  // perfil; el importer NO los consulta — usamos un superset estable
  // de sinónimos comunes en el comercio colombiano. El orden de
  // sinónimos es informativo (proposeMapping toma el primero que matcha
  // cada header, sin priorización entre sinónimos del mismo target).
  'price_tier_1': [
    'precio tier 1',
    'precio_tier_1',
    'price tier 1',
    'price_tier_1',
    'tier 1',
    'tier_1',
    'precio mayorista',
    'mayorista',
    'precio mayorista x12',
    'mayorista x12',
    'precio deposito',
    'precio depósito',
    'deposito',
    'depósito',
    'precio contado',
    'contado',
  ],
  'price_tier_2': [
    'precio tier 2',
    'precio_tier_2',
    'price tier 2',
    'price_tier_2',
    'tier 2',
    'tier_2',
    'precio mayorista x6',
    'mayorista x6',
    'precio credito',
    'precio crédito',
    'credito',
    'crédito',
    'precio deposito credito',
    'precio depósito crédito',
  ],
  'price_tier_3': [
    'precio tier 3',
    'precio_tier_3',
    'price tier 3',
    'price_tier_3',
    'tier 3',
    'tier_3',
    'precio detal',
    'detal',
    'precio minorista',
    'minorista',
    'precio cliente final',
    'cliente final',
  ],
};

/// Helper de normalización Unicode → ASCII básico.
/// Reemplaza vocales con tilde, diéresis y ñ; case-insensitive.
/// Espejo exacto del _normalize() en customer_import_mapper.dart.
String _normalize(String s) {
  const map = {
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
    buf.write(map[c] ?? c);
  }
  return buf.toString().toLowerCase().trim();
}

/// Servicio de mapeo e importación de productos.
class ProductImportMapper {
  ProductImportMapper._();

  /// Normaliza un header para comparación. Expuesto para tests.
  static String normalizeHeader(String h) => _normalize(h.trim());

  /// Propone un mapeo automático dado una lista de headers del archivo.
  ///
  /// Devuelve `Map<int, String?>` donde la clave es el índice del header y
  /// el valor es el target column (ver [kProductTargets]) o `null` si el
  /// header no se reconoce.
  ///
  /// Regla: si dos headers mapean al mismo target, el primero gana.
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

  /// Normaliza un string de precio en formato colombiano a un double.
  ///
  /// Heurística (espejo del backend NormalizePriceCOP):
  ///   - Quita '$', espacios en blanco alrededor.
  ///   - Si contiene TANTO punto COMO coma: el último separador es el
  ///     decimal. Ej: "1.500,50" → 1500.50; "1,500.00" → 1500.00.
  ///   - Si solo tiene punto: en Colombia el punto es separador de miles
  ///     cuando está en posición \d{1,3}(\.\d{3})+ → quitarlo y parsear
  ///     como entero. Si parece decimal (ej. "1500.50") → usar como decimal.
  ///   - Si solo tiene coma: si tiene 3+ dígitos a la derecha → miles;
  ///     si <= 2 dígitos a la derecha → decimal.
  ///   - Retorna null si el número no parsea, es <= 0 o es vacío.
  static double? normalizePriceCOP(String raw) {
    // Strip currency symbols and extra spaces
    var s = raw
        .replaceAll(r'$', '')
        .replaceAll(' ', ' ') // non-breaking space
        .trim();

    if (s.isEmpty) return null;

    final hasDot = s.contains('.');
    final hasComma = s.contains(',');

    double? value;

    if (hasDot && hasComma) {
      // Both separators: last one is decimal
      final lastDot = s.lastIndexOf('.');
      final lastComma = s.lastIndexOf(',');
      if (lastComma > lastDot) {
        // European format: 1.500,50 → decimal comma
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // English format: 1,500.00 → decimal dot
        s = s.replaceAll(',', '');
      }
      value = double.tryParse(s);
    } else if (hasDot && !hasComma) {
      // Dot only: check if it's thousands or decimal
      // \d{1,3}(\.\d{3})+ pattern = thousands
      final thousandsPattern = RegExp(r'^\d{1,3}(\.\d{3})+$');
      if (thousandsPattern.hasMatch(s)) {
        // Colombian thousands: 1.500 → 1500
        s = s.replaceAll('.', '');
      }
      // else leave as-is (decimal dot: 1500.50)
      value = double.tryParse(s);
    } else if (!hasDot && hasComma) {
      // Comma only: check if it's thousands or decimal
      final afterComma = s.split(',').last;
      if (afterComma.length == 3) {
        // Likely thousands: 1,500 → 1500
        s = s.replaceAll(',', '');
      } else {
        // Decimal comma: 1500,50 → 1500.50
        s = s.replaceAll(',', '.');
      }
      value = double.tryParse(s);
    } else {
      // No separators: plain integer
      value = double.tryParse(s);
    }

    if (value == null || value <= 0) return null;
    return value;
  }

  /// Valida una fila ya mapeada (map de targetColumn → valor).
  ///
  /// Reglas de producto (FR-03, FR-11, spec §7):
  ///   - `name` no vacío (mínimo 1 char tras trim).
  ///   - `price` no vacío Y parseable Y > 0 (vía normalizePriceCOP).
  ///   - `stock` si presente: parseable como número, >= 0 (decimales → ok,
  ///     pero se redondean; negativos → fallo).
  static ValidationResult validateRow(Map<String, dynamic> row) {
    // Validate name
    final rawName = row['name'];
    final name =
        (rawName as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) {
      return const ValidationResult.fail('nombre vacío');
    }

    // Validate price
    final rawPrice = row['price'];
    final priceStr = (rawPrice as String? ?? '').trim();
    if (priceStr.isEmpty) {
      return const ValidationResult.fail('precio vacío o no mapeado');
    }
    final parsedPrice = normalizePriceCOP(priceStr);
    if (parsedPrice == null) {
      return ValidationResult.fail(
          'precio inválido: "$priceStr" no es un número mayor a 0');
    }

    // Validate stock (optional field)
    final rawStock = row['stock'];
    if (rawStock != null) {
      final stockStr = rawStock.toString().trim();
      if (stockStr.isNotEmpty) {
        final stockVal = double.tryParse(stockStr);
        if (stockVal == null) {
          return ValidationResult.fail(
              'stock inválido: "$stockStr" no es un número');
        }
        if (stockVal < 0) {
          return const ValidationResult.fail('stock negativo no permitido');
        }
      }
    }

    return const ValidationResult.ok();
  }

  /// Retorna `true` si el campo stock de una fila tiene valor decimal
  /// (para mostrar warning en el preview).
  static bool stockHasDecimalWarning(Map<String, dynamic> row) {
    final rawStock = row['stock'];
    if (rawStock == null) return false;
    final stockStr = rawStock.toString().trim();
    if (stockStr.isEmpty) return false;
    final stockVal = double.tryParse(stockStr);
    if (stockVal == null) return false;
    return stockVal != stockVal.roundToDouble();
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
