// Spec: specs/043-menu-restaurante-recetas/spec.md
//
// Editor de "Importar menú desde la cámara" (F043, Fase 2). Recibe los platos
// que la IA leyó de la foto de la carta (nombre, descripción, precio, porción,
// categoría) y deja que el tendero los revise/edite/elimine antes de
// publicarlos. Al guardar, cada plato se crea como Product con
// is_menu_item=true → alimenta la sección "Menú restaurante" del catálogo
// público (Fase 3). Todo editable (Art. I: cero fricción, tenderos 50+).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_input.dart';

/// Categorías sugeridas por la IA (spec §6, decisión 5). Texto libre permitido
/// pero el selector ofrece estas para no obligar a teclear.
const List<String> kMenuCategories = [
  'Entradas',
  'Platos fuertes',
  'Bebidas',
  'Postres',
  'Adiciones',
  'Otros',
];

/// Un plato editable en memoria. Mutable a propósito: es estado local de un
/// formulario, no un modelo de dominio (Art. de inmutabilidad aplica a datos
/// compartidos, no a controladores de un editor efímero).
class EditableDish {
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController price;
  final TextEditingController portion;
  String category;

  EditableDish({
    required String name,
    required String description,
    required int price,
    required String portion,
    required this.category,
  })  : name = TextEditingController(text: name),
        description = TextEditingController(text: description),
        price = TextEditingController(text: price > 0 ? price.toString() : ''),
        portion = TextEditingController(text: portion);

  factory EditableDish.fromScan(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final price = rawPrice is num ? rawPrice.round() : 0;
    final cat = (json['category'] as String?)?.trim();
    return EditableDish(
      name: (json['name'] as String?)?.trim() ?? '',
      description: (json['description'] as String?)?.trim() ?? '',
      price: price,
      portion: (json['portion'] as String?)?.trim() ?? '',
      category: (cat != null && cat.isNotEmpty) ? cat : 'Platos fuertes',
    );
  }

  factory EditableDish.empty() => EditableDish(
        name: '',
        description: '',
        price: 0,
        portion: '',
        category: 'Platos fuertes',
      );

  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    portion.dispose();
  }

  bool get isValid => name.text.trim().length >= 2;

  Map<String, dynamic> toCreatePayload() {
    final priceVal = int.tryParse(price.text.replaceAll('.', '').trim()) ?? 0;
    final data = <String, dynamic>{
      'name': name.text.trim(),
      'price': priceVal,
      'stock': 0, // los platos del menú no llevan inventario por unidad
      'category': category,
      'is_menu_item': true,
    };
    final desc = description.text.trim();
    if (desc.isNotEmpty) data['description'] = desc;
    final port = portion.text.trim();
    if (port.isNotEmpty) data['portion'] = port;
    return data;
  }
}

class MenuImportScreen extends StatefulWidget {
  /// Platos crudos devueltos por `POST /menu/scan-photo`.
  final List<Map<String, dynamic>> scannedDishes;

  /// Inyectable para tests; en producción usa el ApiService default.
  final ApiService? apiOverride;

  const MenuImportScreen({
    super.key,
    required this.scannedDishes,
    this.apiOverride,
  });

  @override
  State<MenuImportScreen> createState() => _MenuImportScreenState();
}

class _MenuImportScreenState extends State<MenuImportScreen> {
  late final List<EditableDish> _dishes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dishes = widget.scannedDishes.map(EditableDish.fromScan).toList();
    if (_dishes.isEmpty) _dishes.add(EditableDish.empty());
  }

  @override
  void dispose() {
    for (final d in _dishes) {
      d.dispose();
    }
    super.dispose();
  }

  void _addDish() {
    HapticFeedback.lightImpact();
    setState(() => _dishes.add(EditableDish.empty()));
  }

  void _removeDish(int index) {
    HapticFeedback.lightImpact();
    final removed = _dishes.removeAt(index);
    setState(() {});
    removed.dispose();
  }

  Future<void> _saveAll() async {
    final valid = _dishes.where((d) => d.isValid).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escribe al menos el nombre de un plato (mínimo 2 letras) para '
            'guardar tu menú.',
            style: TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final api = widget.apiOverride ?? ApiService(AuthService());
    var created = 0;
    final errors = <String>[];

    for (final dish in valid) {
      try {
        await api.createProduct(dish.toCreatePayload());
        created++;
      } on AppError catch (e) {
        errors.add('${dish.name.text.trim()}: ${e.message}');
      } catch (e) {
        errors.add('${dish.name.text.trim()}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (created > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errors.isEmpty
                ? '¡Listo! Guardamos $created plato(s) en tu menú. Ya aparecen '
                    'en tu catálogo en línea.'
                : 'Guardamos $created plato(s). ${errors.length} no se '
                    'pudieron guardar.',
            style: const TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos guardar tu menú. ${errors.isNotEmpty ? errors.first : 'Intenta de nuevo.'}',
            style: const TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Revisa tu menú'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'La IA leyó ${_dishes.length} plato(s) de tu carta. Revisa el '
              'nombre, precio y descripción — puedes editar, agregar o quitar '
              'lo que quieras antes de publicarlo.',
              style: const TextStyle(
                  fontSize: 14, color: Colors.black54, height: 1.3),
            ),
          ),
          Expanded(
            child: ListView.separated(
              key: const Key('menu_import_list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              itemCount: _dishes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _DishCard(
                key: ValueKey(_dishes[i]),
                dish: _dishes[i],
                index: i,
                api: widget.apiOverride,
                onRemove: () => _removeDish(i),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _saving
          ? null
          : FloatingActionButton.extended(
              key: const Key('menu_import_add'),
              heroTag: 'menu_add',
              onPressed: _addDish,
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar plato'),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            key: const Key('menu_import_save'),
            onPressed: _saving ? null : _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saving ? 'Guardando…' : 'Publicar en mi menú',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _DishCard extends StatefulWidget {
  final EditableDish dish;
  final int index;
  final VoidCallback onRemove;
  final ApiService? api;

  const _DishCard({
    super.key,
    required this.dish,
    required this.index,
    required this.onRemove,
    this.api,
  });

  @override
  State<_DishCard> createState() => _DishCardState();
}

class _DishCardState extends State<_DishCard> {
  bool _generatingDesc = false;

  /// Genera la descripción del plato con IA a partir del nombre + categoría
  /// y la precarga en el campo (el tendero la edita). Necesita un nombre.
  Future<void> _generateDescription() async {
    final d = widget.dish;
    final name = d.name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escribe primero el nombre del plato.',
            style: TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _generatingDesc = true);
    try {
      final api = widget.api ?? ApiService(AuthService());
      final desc = await api.generateMenuDescription(
        name: name,
        category: d.category,
      );
      if (!mounted) return;
      if (desc.isNotEmpty) {
        d.description.text = desc;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos generar la descripción. Intenta de nuevo.',
              style: TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } on AppError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message, style: const TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos generar la descripción. Intenta de nuevo.',
              style: TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _generatingDesc = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dish;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: d.name,
                  label: 'Nombre del plato',
                  hint: 'Ej: Bandeja Paisa',
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              IconButton(
                key: Key('menu_dish_remove_${widget.index}'),
                tooltip: 'Quitar plato',
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              // Genera la descripción con IA desde el nombre del plato.
              TextButton.icon(
                key: Key('menu_dish_ai_desc_${widget.index}'),
                onPressed: _generatingDesc ? null : _generateDescription,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: _generatingDesc
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF7C3AED)),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_generatingDesc ? 'Generando…' : 'Descripción con IA',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          _Field(
            controller: d.description,
            label: 'Descripción',
            hint: 'Ingredientes o detalles (opcional)',
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: d.price,
                  label: 'Precio',
                  hint: '0',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  prefix: '\$ ',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  controller: d.portion,
                  label: 'Porción',
                  hint: 'Ej: Personal',
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CategorySelector(
            value: d.category,
            onChanged: (v) => setState(() => d.category = v),
          ),
        ],
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CategorySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Categoría',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kMenuCategories.map((cat) {
            final selected = cat == value;
            return ChoiceChip(
              label: Text(cat),
              selected: selected,
              onSelected: (_) => onChanged(cat),
              labelStyle: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.surfaceGrey,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: BorderSide.none,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? prefix;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black54)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
