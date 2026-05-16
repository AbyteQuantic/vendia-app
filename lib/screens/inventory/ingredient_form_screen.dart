// Spec: specs/001-insumos-recetas/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/ingredient.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Formulario de alta/edición de un insumo (Feature 001).
///
/// Cero fricción (Art. I): defaults sensatos — unidad `unidad`, stock y
/// mínimo en 0 — para que la tendera solo escriba lo imprescindible. El
/// stock inicial se envía en el POST de creación; en edición el stock NO
/// se toca aquí porque solo cambia por kardex (spec §7, plan §4).
class IngredientFormScreen extends StatefulWidget {
  /// Insumo a editar; `null` crea uno nuevo.
  final Ingredient? existing;

  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const IngredientFormScreen({super.key, this.existing, this.api});

  @override
  State<IngredientFormScreen> createState() => _IngredientFormScreenState();
}

class _IngredientFormScreenState extends State<IngredientFormScreen> {
  late final ApiService _api =
      widget.api ?? ApiService(AuthService());

  final _nameCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  String _unit = 'unidad';
  bool _saving = false;
  String? _nameError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _unit = e.unit;
      _stockCtrl.text = _trim(e.stock);
      _minStockCtrl.text = _trim(e.minStock);
      _costCtrl.text = _trim(e.unitCost);
    }
  }

  /// Quita el `.0` cuando el número es entero — la tendera no escribe
  /// decimales si no los necesita.
  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  double _parseNumber(TextEditingController ctrl) {
    final raw = ctrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Escriba el nombre del insumo');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });

    final ingredient = Ingredient(
      uuid: widget.existing?.uuid ?? const Uuid().v4(),
      name: name,
      unit: _unit,
      stock: _parseNumber(_stockCtrl),
      minStock: _parseNumber(_minStockCtrl),
      unitCost: _parseNumber(_costCtrl),
    );

    try {
      if (_isEditing) {
        // En edición no se envía `stock` — solo lo muta el kardex.
        final payload = ingredient.toJson()..remove('stock');
        await _api.updateIngredient(ingredient.uuid, payload);
      } else {
        await _api.createIngredient(ingredient.toJson());
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      // El error real se registra; nunca se silencia (Constitución).
      developer.log(
        'Error al guardar el insumo',
        name: 'IngredientFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar el insumo. Intente de nuevo.',
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEditing ? 'Editar insumo' : 'Nuevo insumo',
          style: const TextStyle(
            fontSize: 22,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Nombre del insumo'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('field_ingredient_name'),
                      controller: _nameCtrl,
                      style: const TextStyle(
                          fontSize: 20, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Ej: Arroz, Pollo, Aceite',
                        errorText: _nameError,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _label('Unidad de medida'),
                    const SizedBox(height: 8),
                    _unitDropdown(),
                    const SizedBox(height: 24),
                    _label(_isEditing
                        ? 'Stock actual (se ajusta por kardex)'
                        : 'Stock inicial'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('field_ingredient_stock'),
                      controller: _stockCtrl,
                      enabled: !_isEditing,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(
                          fontSize: 20, color: AppTheme.textPrimary),
                      decoration: const InputDecoration(hintText: '0'),
                    ),
                    const SizedBox(height: 24),
                    _label('Avisar cuando baje de'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('field_ingredient_min'),
                      controller: _minStockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(
                          fontSize: 20, color: AppTheme.textPrimary),
                      decoration: const InputDecoration(hintText: '0'),
                    ),
                    const SizedBox(height: 24),
                    _label('Costo por ${Ingredient.unitLabels[_unit]}'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('field_ingredient_cost'),
                      controller: _costCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          fontSize: 20, color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        prefixText: '\$ ',
                        hintText: '0',
                      ),
                    ),
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
                  key: const Key('btn_save_ingredient'),
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
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
                      : Text(
                          _isEditing ? 'Guardar cambios' : 'Guardar insumo',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      );

  Widget _unitDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('field_ingredient_unit'),
          value: _unit,
          isExpanded: true,
          style: const TextStyle(
            fontSize: 20,
            color: AppTheme.textPrimary,
            fontFamily: 'Roboto',
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          items: Ingredient.validUnits
              .map((u) => DropdownMenuItem<String>(
                    value: u,
                    child: Text(Ingredient.unitLabels[u] ?? u),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              HapticFeedback.selectionClick();
              setState(() => _unit = val);
            }
          },
        ),
      ),
    );
  }
}
