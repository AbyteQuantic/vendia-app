// Spec: specs/043-menu-restaurante-recetas/spec.md
//
// "Ver mis recetas/platos": el módulo de Recetas solo permitía CREAR (3 caminos
// en RecipesHomeScreen) — no había forma de ver/eliminar las recetas ya armadas
// (auditoría capacidades). Esta pantalla lista las recetas con su costo y
// ganancia, permite ver el desglose de ingredientes y eliminar. Reusa el API
// existente (GET /recipes, DELETE /recipes/:uuid).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/recipe.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import 'recipe_step1_screen.dart';

class RecipeListScreen extends StatefulWidget {
  /// Inyección para pruebas de widget.
  final ApiService? apiOverride;
  const RecipeListScreen({super.key, this.apiOverride});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  late final ApiService _api;
  List<Recipe> _recipes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final raw = await _api.fetchRecipes();
      final list = raw
          .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _recipes = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AppError ? e.message : 'No se pudieron cargar las recetas';
      });
    }
  }

  Future<void> _createNew() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecipeStep1Screen()),
    );
    if (mounted) _load();
  }

  Future<void> _confirmDelete(Recipe r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('¿Eliminar "${r.productName}"?',
            style: const TextStyle(fontSize: 21)),
        content: const Text(
          'Se quita del menú. Esta acción no se puede deshacer.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(fontSize: 16, color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteRecipe(r.uuid);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _recipes = _recipes.where((x) => x.uuid != r.uuid).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is AppError ? e.message : 'No se pudo eliminar'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  void _showDetail(Recipe r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RecipeDetailSheet(recipe: r),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Mis recetas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Nueva receta',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'Reintentar',
        onAction: _load,
      );
    }
    if (_recipes.isEmpty) {
      return _MessageState(
        icon: Icons.restaurant_menu_rounded,
        title: 'Aún no tiene recetas',
        subtitle: 'Arme un plato y vea su costo y ganancia.',
        actionLabel: 'Crear receta',
        onAction: _createNew,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _recipes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _RecipeCard(
        recipe: _recipes[i],
        onTap: () => _showDetail(_recipes[i]),
        onDelete: () => _confirmDelete(_recipes[i]),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _RecipeCard(
      {required this.recipe, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final profit = recipe.profitPerUnit;
    final profitColor = profit >= 0 ? AppTheme.success : AppTheme.error;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                      'Precio ${formatCOP(recipe.salePrice)} · Costo ${formatCOP(recipe.productionCost)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ganancia ${formatCOP(profit)} (${recipe.profitMargin.toStringAsFixed(0)}%) · ${recipe.ingredients.length} ${recipe.ingredients.length == 1 ? "insumo" : "insumos"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: profitColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error, size: 26),
                tooltip: 'Eliminar',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    final hasPhoto = recipe.photoUrl != null && recipe.photoUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPhoto
            ? Image.network(recipe.photoUrl!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _emojiBox())
            : _emojiBox(),
      ),
    );
  }

  Widget _emojiBox() => Container(
        color: const Color(0xFFFDEBE3),
        alignment: Alignment.center,
        child: Text(recipe.emoji ?? '🍽️', style: const TextStyle(fontSize: 26)),
      );
}

class _RecipeDetailSheet extends StatelessWidget {
  final Recipe recipe;
  const _RecipeDetailSheet({required this.recipe});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.borderColor,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(recipe.productName,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            if (recipe.category.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(recipe.category,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary)),
              ),
            const SizedBox(height: 16),
            _row('Precio de venta', formatCOP(recipe.salePrice)),
            _row('Costo de insumos', formatCOP(recipe.productionCost)),
            _row(
              'Ganancia por unidad',
              '${formatCOP(recipe.profitPerUnit)} (${recipe.profitMargin.toStringAsFixed(0)}%)',
              color: recipe.profitPerUnit >= 0
                  ? AppTheme.success
                  : AppTheme.error,
            ),
            const Divider(height: 28),
            const Text('Ingredientes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (recipe.ingredients.isEmpty)
              const Text('Sin ingredientes registrados',
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary))
            else
              ...recipe.ingredients.map((ing) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${ing.productName} × ${ing.quantity}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        Text(formatCOP(ing.totalCost),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 15, color: AppTheme.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color ?? AppTheme.textPrimary)),
          ],
        ),
      );
}

/// Estado de mensaje (vacío / error) con CTA — UI_RULES §8.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  const _MessageState({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView para que el RefreshIndicator funcione incluso vacío.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(icon, size: 72, color: AppTheme.borderColor),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: AppTheme.textSecondary)),
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(actionLabel, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
