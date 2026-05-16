/// Recipe model for VendIA POS system.
/// Transforms raw ingredients into sellable menu products (e.g., Hot Dog).
class Recipe {
  final String uuid;
  final String productName;
  final String category; // e.g., "Perros Calientes", "Hamburguesas"
  final double salePrice;
  final String? emoji;
  final String? photoUrl;
  final List<RecipeIngredient> ingredients;
  final DateTime createdAt;
  final int? serverId;

  Recipe({
    required this.uuid,
    required this.productName,
    required this.salePrice,
    this.category = '',
    this.emoji,
    this.photoUrl,
    this.ingredients = const [],
    DateTime? createdAt,
    this.serverId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Total cost of all ingredients for one unit
  double get productionCost =>
      ingredients.fold(0.0, (sum, ing) => sum + ing.totalCost);

  /// Profit per unit in COP
  double get profitPerUnit => salePrice - productionCost;

  /// Profit margin as percentage
  double get profitMargin =>
      salePrice > 0 ? (profitPerUnit / salePrice) * 100 : 0;

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      uuid: json['uuid'] as String,
      productName: json['product_name'] as String,
      salePrice: (json['sale_price'] as num).toDouble(),
      category: json['category'] as String? ?? '',
      emoji: json['emoji'] as String?,
      photoUrl: json['photo_url'] as String?,
      ingredients: (json['ingredients'] as List?)
              ?.map((e) =>
                  RecipeIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      serverId: json['id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'product_name': productName,
        'sale_price': salePrice,
        'category': category,
        'emoji': emoji,
        'photo_url': photoUrl,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
      };
}

/// Single ingredient in a recipe with quantity and cost.
///
/// El contrato del backend (Feature 001) identifica cada insumo de la
/// receta con `ingredient_uuid`. `fromJson` mantiene un fallback a
/// `product_uuid` por compatibilidad con datos viejos antes del cambio
/// de contrato.
class RecipeIngredient {
  /// UUID del insumo. El contrato lo expone como `ingredient_uuid`.
  final String ingredientUuid;
  final String productName;
  final double quantity;
  final double unitCost;
  final String? emoji;

  RecipeIngredient({
    required this.ingredientUuid,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.emoji,
  });

  double get totalCost => quantity * unitCost;

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      // Contrato nuevo: `ingredient_uuid`. Fallback a `product_uuid`
      // para no romper recetas guardadas antes del cambio de contrato.
      ingredientUuid: (json['ingredient_uuid'] ?? json['product_uuid'])
          as String,
      productName: json['product_name'] as String? ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      emoji: json['emoji'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'ingredient_uuid': ingredientUuid,
        'quantity': quantity,
      };
}
