// Spec: specs/095-variantes-producto/spec.md
//
// Generador de combinaciones talla×color. Reemplaza el alta manual
// repetida (ej. crear 6 productos uno por uno para 3 tallas x 2 colores)
// — hallazgo de la verificación adversarial de UX: la carga incremental
// multiplicaba el trabajo 4-6x. El tendero solo escribe los VALORES por
// atributo (ej. "S,M,L") y ve el total de combinaciones ANTES de confirmar
// (Cero Fricción Cognitiva — nunca una sorpresa).

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

class _AttributeRow {
  final TextEditingController labelCtrl;
  final TextEditingController valuesCtrl;
  _AttributeRow()
      : labelCtrl = TextEditingController(),
        valuesCtrl = TextEditingController();

  void dispose() {
    labelCtrl.dispose();
    valuesCtrl.dispose();
  }

  /// Valores no vacíos, recortados. Ej. " S , M ,L " → [S, M, L].
  List<String> get values => valuesCtrl.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  bool get isUsable => labelCtrl.text.trim().isNotEmpty && values.isNotEmpty;
}

class ProductVariantBuilder extends StatefulWidget {
  const ProductVariantBuilder({
    super.key,
    required this.groupNameController,
    required this.basePriceController,
    required this.baseStockController,
    required this.onGenerate,
  });

  final TextEditingController groupNameController;
  final TextEditingController basePriceController;
  final TextEditingController baseStockController;

  /// Se llama al confirmar, con el mapa {atributo: [valores]} ya validado
  /// (al menos un atributo con al menos un valor).
  final Future<void> Function(Map<String, List<String>> attributes) onGenerate;

  @override
  State<ProductVariantBuilder> createState() => _ProductVariantBuilderState();
}

class _ProductVariantBuilderState extends State<ProductVariantBuilder> {
  final List<_AttributeRow> _rows = [_AttributeRow()];
  bool _generating = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Map<String, List<String>> get _usableAttributes {
    final map = <String, List<String>>{};
    for (final r in _rows) {
      if (r.isUsable) map[r.labelCtrl.text.trim()] = r.values;
    }
    return map;
  }

  int get _combinationCount {
    final attrs = _usableAttributes;
    if (attrs.isEmpty) return 0;
    return attrs.values.fold(1, (acc, values) => acc * values.length);
  }

  void _addRow() => setState(() => _rows.add(_AttributeRow()));

  Future<void> _submit() async {
    setState(() => _generating = true);
    try {
      await widget.onGenerate(_usableAttributes);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _combinationCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Variantes (talla, color, presentación)',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        const SizedBox(height: AppUI.s8),
        for (var i = 0; i < _rows.length; i++) ...[
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: Key('variant_attr_label_$i'),
                  controller: _rows[i].labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Atributo', hintText: 'Talla'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppUI.s8),
              Expanded(
                flex: 3,
                child: TextField(
                  key: Key('variant_attr_values_$i'),
                  controller: _rows[i].valuesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Valores separados por coma',
                      hintText: 'S,M,L'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppUI.s8),
        ],
        TextButton.icon(
          key: const Key('variant_add_attribute'),
          onPressed: _addRow,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar atributo (ej. Color)'),
        ),
        const SizedBox(height: AppUI.s8),
        if (count > 0)
          Text('$count producto${count == 1 ? '' : 's'} se crearán con estas combinaciones',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: AppUI.s16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const Key('variant_generate_button'),
            onPressed: (count > 0 && !_generating) ? _submit : null,
            child: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(count > 0 ? 'Generar $count variantes' : 'Generar variantes'),
          ),
        ),
      ],
    );
  }
}
