import 'dart:convert';

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
  // Spec 065 — metadatos de preparación (Recipe Studio). `yield` es palabra
  // reservada en Dart, así que el campo se llama recipeYield.
  final String recipeYield;
  final String prepTime;

  /// Pasos de preparación: lista de {text, photo_url}. El backend los guarda
  /// como JSONB; en el JSON llega como string que aquí se decodifica.
  final List<Map<String, dynamic>> prepSteps;
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
    this.recipeYield = '',
    this.prepTime = '',
    this.prepSteps = const [],
    DateTime? createdAt,
    this.serverId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Decodifica prep_steps que puede venir como String JSON, List ya parseada,
  /// o null. Siempre devuelve una lista de mapas {text, photo_url}.
  static List<Map<String, dynamic>> parseSteps(dynamic raw) {
    if (raw == null) return const [];
    dynamic decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Total cost of all ingredients for one unit
  double get productionCost =>
      ingredients.fold(0.0, (sum, ing) => sum + ing.totalCost);

  /// Profit per unit in COP
  double get profitPerUnit => salePrice - productionCost;

  /// Profit margin as percentage
  double get profitMargin =>
      salePrice > 0 ? (profitPerUnit / salePrice) * 100 : 0;

  // Spec 065 — costeo POR PORCIÓN. Las cantidades de los insumos rinden
  // `servings` porciones; el precio es por una. Mín. 1 (vacío ⇒ una porción,
  // retrocompatible).
  int get servings {
    final m = RegExp(r'\d+').firstMatch(recipeYield);
    final n = m == null ? 1 : int.tryParse(m.group(0)!) ?? 1;
    return n < 1 ? 1 : n;
  }

  double get costPerServing => productionCost / servings;
  double get profitPerServing => salePrice - costPerServing;
  double get marginPerServing =>
      salePrice > 0 ? (profitPerServing / salePrice) * 100 : 0;

  factory Recipe.fromJson(Map<String, dynamic> json) {
    // El backend serializa el ID del BaseModel como `id` (UUID string).
    // `uuid` queda como respaldo para datos offline viejos. (BUG-6)
    final id = (json['id'] ?? json['uuid']) as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException(
          'Recipe.fromJson: falta el identificador (id/uuid)');
    }
    return Recipe(
      uuid: id,
      productName: json['product_name'] as String,
      salePrice: (json['sale_price'] as num).toDouble(),
      category: json['category'] as String? ?? '',
      emoji: json['emoji'] as String?,
      photoUrl: json['photo_url'] as String?,
      recipeYield: json['yield'] as String? ?? '',
      prepTime: json['prep_time'] as String? ?? '',
      prepSteps: parseSteps(json['prep_steps']),
      ingredients: (json['ingredients'] as List?)
              ?.map((e) =>
                  RecipeIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
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
