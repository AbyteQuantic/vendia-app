// Spec: specs/001-insumos-recetas/spec.md
/// Modelo Ingredient (insumo) para VendIA POS.
///
/// Un insumo es materia prima de inventario — distinto del producto
/// vendible. Las recetas consumen insumos al vender (Feature 001). El
/// stock de un insumo solo cambia por movimientos de kardex; el cliente
/// muestra el último valor sincronizado (spec §5, D2).
class Ingredient {
  final String uuid;
  final String name;

  /// Unidad de medida. Enum fijo (spec D5): unidad | g | kg | ml | l.
  final String unit;
  final double stock;
  final double minStock;

  /// Costo unitario en COP, usado para el roll-up de costo de receta.
  final double unitCost;
  final DateTime? expiryDate;
  final String? supplierId;
  final DateTime createdAt;
  final int? serverId;

  Ingredient({
    required this.uuid,
    required this.name,
    this.unit = 'unidad',
    this.stock = 0,
    this.minStock = 0,
    this.unitCost = 0,
    this.expiryDate,
    this.supplierId,
    DateTime? createdAt,
    this.serverId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Enum fijo de unidades válidas (spec D5).
  static const List<String> validUnits = ['unidad', 'g', 'kg', 'ml', 'l'];

  /// Etiquetas legibles en español para cada unidad.
  static const Map<String, String> unitLabels = {
    'unidad': 'Unidades',
    'g': 'Gramos',
    'kg': 'Kilogramos',
    'ml': 'Mililitros',
    'l': 'Litros',
  };

  /// Etiqueta legible de la unidad de este insumo.
  String get unitLabel => unitLabels[unit] ?? unit;

  /// Insumo bajo el mínimo (AC-05). Un mínimo de 0 desactiva la alerta.
  bool get isLowStock => minStock > 0 && stock <= minStock;

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String? ?? 'unidad',
      stock: (json['stock'] as num?)?.toDouble() ?? 0,
      minStock: (json['min_stock'] as num?)?.toDouble() ?? 0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      expiryDate: json['expiry_date'] != null
          ? DateTime.tryParse(json['expiry_date'] as String)
          : null,
      supplierId: json['supplier_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      serverId: json['id'] as int?,
    );
  }

  /// Serializa los campos que el backend espera en POST/PATCH (plan §4).
  /// Los campos nullable se omiten cuando son nulos para no enviar
  /// strings vacíos que rompan el insert en Postgres (Art. X).
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'uuid': uuid,
      'name': name,
      'unit': unit,
      'stock': stock,
      'min_stock': minStock,
      'unit_cost': unitCost,
    };
    if (expiryDate != null) {
      json['expiry_date'] = expiryDate!.toUtc().toIso8601String();
    }
    if (supplierId != null && supplierId!.isNotEmpty) {
      json['supplier_id'] = supplierId;
    }
    return json;
  }

  /// Copia inmutable con los campos indicados sobreescritos (Art. IX).
  Ingredient copyWith({
    String? uuid,
    String? name,
    String? unit,
    double? stock,
    double? minStock,
    double? unitCost,
    DateTime? expiryDate,
    String? supplierId,
    DateTime? createdAt,
    int? serverId,
  }) {
    return Ingredient(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      unitCost: unitCost ?? this.unitCost,
      expiryDate: expiryDate ?? this.expiryDate,
      supplierId: supplierId ?? this.supplierId,
      createdAt: createdAt ?? this.createdAt,
      serverId: serverId ?? this.serverId,
    );
  }
}
