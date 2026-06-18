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
import '../../theme/app_ui.dart';
import '../../utils/format_cop.dart';
import 'recipe_studio_screen.dart';

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
      MaterialPageRoute(builder: (_) => const RecipeStudioScreen()),
    );
    if (mounted) _load();
  }

  /// Abre el Recipe Studio en modo EDICIÓN con la receta precargada.
  Future<void> _edit(Recipe r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeStudioScreen(editing: r)),
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
      builder: (sheetCtx) => _RecipeDetailSheet(
        recipe: r,
        onEdit: () {
          Navigator.of(sheetCtx).pop();
          _edit(r);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Mis recetas', style: AppUI.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppUI.s8),
            child: GhostButton(
              icon: Icons.add_rounded,
              label: 'Nueva',
              color: AppTheme.primary,
              onPressed: _createNew,
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
    final profit = recipe.profitPerServing;
    final profitColor = profit >= 0 ? AppTheme.success : AppTheme.error;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUI.radius),
        child: Container(
          padding: const EdgeInsets.all(AppUI.s12),
          decoration: AppUI.card(),
          child: Row(
            children: [
              _thumb(),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppUI.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'Precio ${formatCOP(recipe.salePrice)} · Costo ${formatCOP(recipe.costPerServing)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUI.bodySoft,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      MinimalBadge(
                        label:
                            '${profit >= 0 ? "+" : ""}${formatCOP(profit)} · ${recipe.marginPerServing.toStringAsFixed(0)}%',
                        color: profitColor,
                      ),
                      const SizedBox(width: AppUI.s8),
                      Text(
                        '${recipe.ingredients.length} ${recipe.ingredients.length == 1 ? "insumo" : "insumos"}',
                        style: AppUI.bodySoft,
                      ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppUI.inkSoft, size: 22),
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
  final VoidCallback onEdit;
  const _RecipeDetailSheet({required this.recipe, required this.onEdit});

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
                    color: AppUI.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(recipe.productName,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Editar', style: TextStyle(fontSize: 15)),
                ),
              ],
            ),
            if (recipe.category.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(recipe.category,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary)),
              ),
            if (recipe.recipeYield.isNotEmpty || recipe.prepTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, children: [
                  if (recipe.recipeYield.isNotEmpty)
                    _chip(Icons.restaurant_rounded, recipe.recipeYield),
                  if (recipe.prepTime.isNotEmpty)
                    _chip(Icons.schedule_rounded, recipe.prepTime),
                ]),
              ),
            const SizedBox(height: 16),
            _row('Precio de venta (por porción)', formatCOP(recipe.salePrice)),
            if (recipe.servings > 1)
              _row('Costo total (${recipe.servings} porciones)',
                  formatCOP(recipe.productionCost)),
            _row('Costo por porción', formatCOP(recipe.costPerServing)),
            _row(
              'Ganancia por porción',
              '${formatCOP(recipe.profitPerServing)} (${recipe.marginPerServing.toStringAsFixed(0)}%)',
              color: recipe.profitPerServing >= 0
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
            if (recipe.prepSteps.isNotEmpty) ...[
              const Divider(height: 28),
              const Text('Preparación',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...recipe.prepSteps.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${e.key + 1}. ${e.value['text'] ?? ''}',
                        style: const TextStyle(fontSize: 15)),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppUI.pageBg,
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          border: Border.all(color: AppUI.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppUI.inkSoft),
          const SizedBox(width: 5),
          Text(label, style: AppUI.bodySoft),
        ]),
      );

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppUI.bodySoft),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color ?? AppUI.ink)),
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
        Icon(icon, size: 56, color: AppUI.inkSoft),
        const SizedBox(height: AppUI.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(title,
              textAlign: TextAlign.center,
              style: AppUI.title),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppUI.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(subtitle!,
                textAlign: TextAlign.center, style: AppUI.bodySoft),
          ),
        ],
        const SizedBox(height: AppUI.s24),
        Center(
          child: GhostButton(
            icon: Icons.add_rounded,
            label: actionLabel,
            color: AppTheme.primary,
            onPressed: onAction,
          ),
        ),
      ],
    );
  }
}
