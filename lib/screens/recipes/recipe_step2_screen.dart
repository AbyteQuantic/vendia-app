// Spec: specs/001-insumos-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/ingredient.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'recipe_step3_screen.dart';

/// Recipe creation step 2: pick real ingredients (insumos) with quantities.
///
/// Feature 001 — des-mockeado: ya NO usa `_MockIngredient`. Carga los
/// insumos reales del tenant con `fetchIngredients` y deja al tendero
/// elegir cuáles consume el plato y en qué cantidad (FR-02, plan §5).
class RecipeStep2Screen extends StatefulWidget {
  final String productName;
  final double salePrice;
  final String emoji;
  final String category;

  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const RecipeStep2Screen({
    super.key,
    required this.productName,
    required this.salePrice,
    required this.emoji,
    this.category = '',
    this.api,
  });

  @override
  State<RecipeStep2Screen> createState() => _RecipeStep2ScreenState();
}

/// Una línea de receta: un insumo real + la cantidad que consume el plato.
class _RecipeLine {
  final Ingredient ingredient;

  /// Cantidad del insumo en su propia unidad. Arranca en 1 y la ajusta
  /// el tendero con los botones +/-.
  double quantity = 1;

  _RecipeLine({required this.ingredient});

  double get totalCost => ingredient.unitCost * quantity;
}

class _RecipeStep2ScreenState extends State<RecipeStep2Screen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  final List<_RecipeLine> _lines = [];
  List<Ingredient> _available = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.fetchIngredients();
      if (!mounted) return;
      setState(() {
        _available = raw.map(Ingredient.fromJson).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar sus insumos.';
        _loading = false;
      });
    }
  }

  double get _totalCost =>
      _lines.fold(0.0, (sum, l) => sum + l.totalCost);

  String _formatNumber(double value) {
    final intVal = value.round();
    return intVal.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  /// Abre el selector con los insumos aún no agregados a la receta.
  Future<void> _pickIngredient() async {
    HapticFeedback.lightImpact();
    final used = _lines.map((l) => l.ingredient.uuid).toSet();
    final choices =
        _available.where((i) => !used.contains(i.uuid)).toList();

    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ya agregó todos sus insumos.',
            style: TextStyle(fontSize: 18),
          ),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<Ingredient>(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Escoja un insumo',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: choices.length,
                itemBuilder: (_, i) => ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(
                    choices[i].name,
                    style: const TextStyle(
                      fontSize: 20,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '\$${_formatNumber(choices[i].unitCost)} '
                    'por ${choices[i].unitLabel.toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(choices[i]),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (picked != null) {
      setState(() => _lines.add(_RecipeLine(ingredient: picked)));
    }
  }

  void _goToStep3() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeStep3Screen(
          productName: widget.productName,
          salePrice: widget.salePrice,
          emoji: widget.emoji,
          category: widget.category,
          api: widget.api,
          ingredients: _lines
              .map((l) => {
                    'uuid': l.ingredient.uuid,
                    'name': l.ingredient.name,
                    'quantity': l.quantity,
                    'unitCost': l.ingredient.unitCost,
                    'unit': l.ingredient.unit,
                  })
              .toList(),
        ),
      ),
    );
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
          'Ingredientes (2/3)',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _loadIngredients,
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _productBanner(),
                const SizedBox(height: 24),
                const Text(
                  '¿Qué gasta para hacer este producto?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                if (_available.isEmpty)
                  _noIngredientsHint()
                else ...[
                  ..._lines.map(_buildLineCard),
                  const SizedBox(height: 16),
                  _addIngredientButton(),
                ],
                const SizedBox(height: 24),
                _costBar(),
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
              key: const Key('btn_recipe_to_step3'),
              onPressed: _lines.isEmpty ? null : _goToStep3,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                disabledBackgroundColor:
                    AppTheme.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ver resumen',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 24),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _productBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Text(
            '\$${_formatNumber(widget.salePrice)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noIngredientsHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: const Column(
        children: [
          Icon(Icons.kitchen_rounded, size: 48, color: AppTheme.warning),
          SizedBox(height: 12),
          Text(
            'No tiene insumos registrados',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Primero registre sus insumos en la pantalla de Insumos '
            'para poder armar la receta.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _addIngredientButton() {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: OutlinedButton.icon(
        key: const Key('btn_pick_ingredient'),
        onPressed: _pickIngredient,
        icon: const Icon(Icons.add_rounded,
            size: 28, color: AppTheme.primary),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.borderColor, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        label: const Text(
          'Agregar Ingrediente',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildLineCard(_RecipeLine line) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.ingredient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${_formatNumber(line.totalCost)} '
                  '(${_formatNumber(line.ingredient.unitCost)} '
                  'por ${line.ingredient.unitLabel.toLowerCase()})',
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _qtyButton(Icons.remove_rounded, () {
            HapticFeedback.lightImpact();
            if (line.quantity > 1) {
              setState(() => line.quantity -= 1);
            }
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '×${_trimQty(line.quantity)}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          _qtyButton(Icons.add_rounded, () {
            HapticFeedback.lightImpact();
            setState(() => line.quantity += 1);
          }),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.error, size: 24),
            tooltip: 'Quitar',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _lines.remove(line));
            },
          ),
        ],
      ),
    );
  }

  String _trimQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 24, color: AppTheme.textPrimary),
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.borderColor),
          ),
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _costBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Flexible(
            child: Text(
              'Costo total de este producto:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Text(
            '\$${_formatNumber(_totalCost)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
