// Spec: specs/001-insumos-recetas/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ingredient.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'ingredient_form_screen.dart';

/// Pantalla de gestión de insumos — materia prima del negocio (Feature 001).
///
/// Lista los insumos del tenant con su stock, unidad y aviso de stock bajo
/// (AC-01, AC-05). Permite crear, editar y eliminar. El stock NO se edita
/// aquí: solo cambia por movimientos de kardex (spec §7, plan §4).
///
/// Cumple UI_RULES: 3 estados visibles (loading/empty/error), header con
/// máximo 2 acciones laterales, márgenes de 20dp y textos ≥18px.
class IngredientsScreen extends StatefulWidget {
  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const IngredientsScreen({super.key, this.api});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  List<Ingredient> _ingredients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.fetchIngredients();
      if (!mounted) return;
      setState(() {
        _ingredients = raw.map(Ingredient.fromJson).toList();
        _loading = false;
      });
    } catch (e, stack) {
      // El detalle técnico NO se le muestra al usuario (UI_RULES §8),
      // pero JAMÁS se silencia: se registra para diagnóstico
      // (Constitución — nunca tragar errores).
      developer.log(
        'Error al cargar los insumos',
        name: 'IngredientsScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar sus insumos.';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Ingredient? existing}) async {
    HapticFeedback.lightImpact();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IngredientFormScreen(
          existing: existing,
          api: widget.api,
        ),
      ),
    );
    if (saved == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Insumo guardado',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _confirmDelete(Ingredient ing) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: const Text(
          'Eliminar insumo',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Seguro que quiere eliminar "${ing.name}"?',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Eliminar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteIngredient(ing.uuid);
      await _load();
    } catch (e, stack) {
      developer.log(
        'Error al eliminar el insumo ${ing.uuid}',
        name: 'IngredientsScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar el insumo.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          tooltip: 'Volver',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Insumos',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('btn_add_ingredient'),
            icon: const Icon(Icons.add_rounded,
                color: AppTheme.primary, size: 30),
            tooltip: 'Agregar insumo',
            onPressed: () => _openForm(),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    if (_ingredients.isEmpty) {
      return _EmptyState(onAdd: () => _openForm());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _ingredients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _IngredientCard(
          ingredient: _ingredients[i],
          onEdit: () => _openForm(existing: _ingredients[i]),
          onDelete: () => _confirmDelete(_ingredients[i]),
        ),
      ),
    );
  }
}

/// Tarjeta de un insumo en la lista.
class _IngredientCard extends StatelessWidget {
  final Ingredient ingredient;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IngredientCard({
    required this.ingredient,
    required this.onEdit,
    required this.onDelete,
  });

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final low = ingredient.isLowStock;
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(24),
          border: low
              ? Border.all(color: AppTheme.warning, width: 2)
              : Border.all(color: AppTheme.borderColor, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ingredient.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_trim(ingredient.stock)} ${ingredient.unitLabel.toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (low) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Stock bajo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppTheme.error, size: 26),
              tooltip: 'Eliminar',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío con CTA — UI_RULES §8.
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.kitchen_rounded,
                size: 72, color: AppTheme.borderColor),
            const SizedBox(height: 16),
            const Text(
              'Aún no tiene insumos',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Registre el arroz, el pollo y demás materia prima '
              'para saber con qué cuenta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 64,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                label: const Text(
                  'Agregar insumo',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado de error con botón Reintentar — UI_RULES §8.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 72, color: AppTheme.borderColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 64,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
                child: const Text(
                  'Reintentar',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
