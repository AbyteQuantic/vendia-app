// Spec: specs/001-insumos-recetas/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Recipe creation step 3: summary + persistencia real de la receta.
///
/// Feature 001 — des-mockeado: el botón "Guardar" ya NO muestra solo un
/// snackbar. Llama `createRecipe` con el contrato de receta (producto +
/// insumos con `ingredient_uuid` y `quantity`) y, cuando hay UUID, pide
/// el costo autoritativo con `fetchRecipeCost` (plan §5, FR-04).
class RecipeStep3Screen extends StatefulWidget {
  final String productName;
  final double salePrice;
  final String emoji;
  final String category;

  /// Cada item: {uuid, name, quantity, unitCost, unit}.
  final List<Map<String, dynamic>> ingredients;

  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const RecipeStep3Screen({
    super.key,
    required this.productName,
    required this.salePrice,
    required this.emoji,
    required this.ingredients,
    this.category = '',
    this.api,
  });

  @override
  State<RecipeStep3Screen> createState() => _RecipeStep3ScreenState();
}

class _RecipeStep3ScreenState extends State<RecipeStep3Screen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  bool _saving = false;

  /// Costo de producción local (fallback hasta que el backend confirme).
  double get _localCost => widget.ingredients.fold(
        0.0,
        (sum, ing) =>
            sum +
            ((ing['unitCost'] as num).toDouble() *
                (ing['quantity'] as num).toDouble()),
      );

  double get _profit => widget.salePrice - _localCost;

  String _formatNumber(double value) {
    final intVal = value.round();
    return intVal.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  /// Construye el payload de receta para el backend.
  ///
  /// Contrato autoritativo de `POST /api/v1/recipes`:
  /// `{ id?, product_name, category, sale_price, emoji, photo_url,
  /// ingredients: [{ ingredient_uuid, quantity }] }`.
  /// Es una receta nueva, así que `id` se omite (es opcional). Cada
  /// insumo viaja SOLO con `ingredient_uuid` y `quantity`.
  Map<String, dynamic> _buildPayload() {
    return {
      'product_name': widget.productName,
      'sale_price': widget.salePrice.round(),
      'category': widget.category,
      'emoji': widget.emoji,
      'ingredients': widget.ingredients
          .map((ing) => {
                'ingredient_uuid': ing['uuid'],
                'quantity': (ing['quantity'] as num).toDouble(),
              })
          .toList(),
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final created = await _api.createRecipe(_buildPayload());
      // Confirmación del costo autoritativo del backend (FR-04). Es
      // best-effort: si el backend no devuelve UUID o el endpoint aún
      // no existe, la receta ya quedó guardada y no bloqueamos al
      // usuario.
      final recipeUuid = created['uuid'] as String?;
      if (recipeUuid != null && recipeUuid.isNotEmpty) {
        try {
          await _api.fetchRecipeCost(recipeUuid);
        } catch (e, stack) {
          // El costo se mostrará con el cálculo local; no es crítico
          // para el usuario, pero el error igual se registra.
          developer.log(
            'No se pudo confirmar el costo autoritativo de la receta',
            name: 'RecipeStep3Screen',
            error: e,
            stackTrace: stack,
          );
        }
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      // Cierra todo el wizard (3 pasos) y vuelve a la pantalla de origen.
      // `popUntil` es seguro aunque la pila tenga otra profundidad.
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '"${widget.productName}" guardado en el menú',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stack) {
      // El detalle técnico no se le muestra al usuario, pero el error
      // se registra; nunca se silencia (Constitución).
      developer.log(
        'Error al guardar la receta',
        name: 'RecipeStep3Screen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar la receta. Intente de nuevo.',
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
          'Resumen (3/3)',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Center(
                        child: Text(widget.emoji,
                            style: const TextStyle(fontSize: 48)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.productName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _ingredientsCard(),
                    const SizedBox(height: 20),
                    _profitBox(),
                  ],
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  key: const Key('btn_save_recipe'),
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    disabledBackgroundColor:
                        AppTheme.success.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Guardar en el Menú',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ingredientsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ingredientes:',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.ingredients.isEmpty)
            const Text(
              'Sin insumos — el costo será 0.',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ...widget.ingredients.map((ing) {
            final name = ing['name'] as String;
            final qty = (ing['quantity'] as num).toDouble();
            final unitCost = (ing['unitCost'] as num).toDouble();
            final total = unitCost * qty;
            final qtyLabel =
                qty == qty.roundToDouble() ? qty.toInt().toString() : '$qty';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$name × $qtyLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '\$${_formatNumber(total)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          const Divider(thickness: 1, color: AppTheme.borderColor),
          const SizedBox(height: 12),
          _summaryRow('Costo de producción:',
              '\$${_formatNumber(_localCost)}', AppTheme.error),
          const SizedBox(height: 8),
          _summaryRow('Precio de venta:',
              '\$${_formatNumber(widget.salePrice)}', AppTheme.textPrimary),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 20,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _profitBox() {
    final positive = _profit >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (positive ? AppTheme.success : AppTheme.error)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (positive ? AppTheme.success : AppTheme.error)
              .withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          positive
              ? '💰 Gana \$${_formatNumber(_profit)} por unidad'
              : '⚠️ Pierde \$${_formatNumber(_profit.abs())} por unidad',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: positive ? AppTheme.success : AppTheme.error,
          ),
        ),
      ),
    );
  }
}
