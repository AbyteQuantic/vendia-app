// Spec: specs/065-recipe-studio/spec.md
//
// "Nuevo plato" — editor de recetas rediseñado por concilio para que un TENDERO
// lo entienda a la primera (antes era un "ERP look" denso y confuso):
//   · Secciones numeradas y humanas: 1. El plato → 2. Ingredientes y costo →
//     3. Preparación (opcional).
//   · LABELS FIJOS arriba de cada campo + ejemplo como ayuda (nunca
//     placeholder-como-label que desaparece al escribir).
//   · IA en UN solo botón opcional ("Que la IA me ayude") con hoja explicativa
//     y chips de ajuste — no una barra ambigua en medio.
//   · Ingredientes con ayuda fija ("usted pone la cantidad, el costo se calcula
//     solo, salen de Inventario") + cantidad editable con decimales.
//   · Barra inferior fija: Costo · Precio · Ganancia + Guardar.
// REGLA DE ORO: NO toca la lógica de costeo (Σ insumo·cantidad) ni el contrato
// createRecipe/updateRecipe — solo UI/flujo/copy.
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ingredient.dart';
import '../../models/recipe.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/quantity_presets.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../inventory/ingredients_screen.dart';
import 'recipe_list_screen.dart';

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

// Sugerencias para autocompletar (normalizan los valores que escribe el
// tendero). Puede elegir una o escribir la suya.
const List<String> _kCategorySuggestions = [
  'Almuerzos', 'Corrientazo', 'Ejecutivo', 'Desayunos', 'Cenas', 'Entradas',
  'Sopas', 'Asados', 'Comidas rápidas', 'Bebidas', 'Jugos', 'Postres',
];
const List<String> _kPresentationSuggestions = [
  'Plato', 'Plato hondo', 'Bandeja', 'Vaso', 'Pocillo', 'Para llevar',
  'Caja', 'En mesa',
];

/// Una línea costeada: un insumo REAL (uuid + unitCost) y la cantidad que
/// consume el plato. El costo se deriva igual que siempre.
class _RecipeLine {
  Ingredient ingredient; // mutable: se puede corregir el costo unitario del insumo
  double quantity;
  final TextEditingController qtyCtrl;
  _RecipeLine(this.ingredient, [double qty = 1])
      : quantity = qty,
        qtyCtrl = TextEditingController(text: _fmtQty(qty));
  double get totalCost => ingredient.unitCost * quantity;
}

/// Un paso de preparación: texto + foto opcional.
class _StepDraft {
  final TextEditingController controller;
  String? photoUrl;
  _StepDraft({String text = ''})
      : controller = TextEditingController(text: text);
}

class RecipeStudioScreen extends StatefulWidget {
  /// Prefill desde voz/IA: {name, description, yield, prep_time,
  /// ingredients:[{name,quantity,unit}], steps:[String]}.
  final Map<String, dynamic>? initial;

  /// Si viene una receta, entra en modo EDICIÓN.
  final Recipe? editing;
  final ApiService? api;

  const RecipeStudioScreen({super.key, this.initial, this.editing, this.api});

  @override
  State<RecipeStudioScreen> createState() => _RecipeStudioScreenState();
}

class _RecipeStudioScreenState extends State<RecipeStudioScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  /// Plato de menú existente a completar (importado sin receta). Spec 078.
  String? _linkProductId;

  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _portionCtrl = TextEditingController();
  final _yieldCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _categoryFocus = FocusNode();
  final _portionFocus = FocusNode();
  String _emoji = '🍽️';

  final List<_RecipeLine> _lines = [];
  final List<_StepDraft> _steps = [];
  List<Ingredient> _available = [];

  String? _photoUrl;
  XFile? _localPhoto;

  bool _loading = true;
  bool _saving = false;
  bool _aiBusy = false;
  bool _photoBusy = false; // foto del plato generándose/subiéndose
  bool _generatingDesc = false; // descripción con IA en curso
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _priceCtrl, _categoryCtrl, _descCtrl,
      _portionCtrl, _yieldCtrl, _timeCtrl, _instructionsCtrl,
    ]) {
      c.dispose();
    }
    for (final s in _steps) {
      s.controller.dispose();
    }
    for (final l in _lines) {
      l.qtyCtrl.dispose();
    }
    _categoryFocus.dispose();
    _portionFocus.dispose();
    super.dispose();
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
      if (widget.editing != null) _applyEditing(widget.editing!);
      if (widget.initial != null) _applyInitial(widget.initial!);
    } catch (e, stack) {
      developer.log('Error al cargar insumos (Studio)',
          name: 'RecipeStudioScreen', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar sus insumos.';
        _loading = false;
      });
    }
  }

  /// Refresca SOLO la lista de insumos disponibles (tras volver de registrar
  /// insumos), sin re-aplicar initial/editing — así NO se pierde lo que el
  /// tendero ya escribió en el plato.
  Future<void> _refreshAvailable() async {
    try {
      final raw = await _api.fetchIngredients();
      if (!mounted) return;
      setState(() => _available = raw.map(Ingredient.fromJson).toList());
    } catch (_) {
      /* deja los insumos actuales */
    }
  }

  // ── Costeo (lógica intacta) ────────────────────────────────────────────
  // Costo TOTAL de los insumos = lo que cuesta hacer TODAS las porciones que
  // el tendero indicó en "Porciones" (lógica Σ intacta).
  double get _totalCost => _lines.fold(0.0, (s, l) => s + l.totalCost);
  double get _salePrice => _parsePrice(_priceCtrl.text);

  /// Cuántas porciones rinde la receta (de "Porciones"). Mínimo 1; vacío ⇒ 1
  /// (retrocompatible: receta = una porción).
  int get _servings {
    final m = RegExp(r'\d+').firstMatch(_yieldCtrl.text);
    final n = m == null ? 1 : int.tryParse(m.group(0)!) ?? 1;
    return n < 1 ? 1 : n;
  }

  /// Costo POR PORCIÓN = costo total ÷ porciones. El precio que pone el tendero
  /// es por una porción, así que la ganancia se compara contra el costo por
  /// porción (esto arregla "puse cantidades para 5 pero calculaba 1").
  double get _costPerServing => _totalCost / _servings;
  double get _profit => _salePrice - _costPerServing;

  /// Solo los dígitos de un texto (para extraer minutos de "60 minutos"/"30 min").
  String _digits(String s) => RegExp(r'\d+').firstMatch(s)?.group(0) ?? '';

  /// Tiempo NORMALIZADO a "<n> min" (canónico, parseable más adelante). Vacío
  /// si no hay número. El campo guarda solo el número; aquí le damos la forma.
  String _normalizedTime() {
    final d = _digits(_timeCtrl.text);
    return d.isEmpty ? '' : '$d min';
  }

  double _parsePrice(String t) =>
      double.tryParse(t.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  String _money(double v) => '\$${v.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      )}';

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty && _salePrice > 0 && _lines.isNotEmpty;

  String get _missingText {
    final m = <String>[];
    if (_nameCtrl.text.trim().isEmpty) m.add('el nombre');
    if (_salePrice <= 0) m.add('el precio');
    if (_lines.isEmpty) m.add('al menos un insumo');
    return 'Falta: ${m.join(', ')}.';
  }

  // ── Prefill desde voz/IA ───────────────────────────────────────────────
  void _applyInitial(Map<String, dynamic> data) {
    setState(() {
      // Completar un plato importado: liga la receta a ese producto (Spec 078).
      _linkProductId = (data['link_product_id'] as String?);
      if ((data['name'] as String?)?.isNotEmpty ?? false) {
        _nameCtrl.text = data['name'] as String;
      }
      if ((data['price'] as num?) != null && _priceCtrl.text.trim().isEmpty) {
        _priceCtrl.text = (data['price'] as num).round().toString();
      }
      if ((data['description'] as String?)?.isNotEmpty ?? false) {
        _descCtrl.text = data['description'] as String;
      }
      if ((data['yield'] as String?)?.isNotEmpty ?? false) {
        _yieldCtrl.text = data['yield'] as String;
      }
      if ((data['prep_time'] as String?)?.isNotEmpty ?? false) {
        _timeCtrl.text = _digits(data['prep_time'] as String);
      }
      final steps = (data['steps'] as List?) ?? const [];
      if (steps.isNotEmpty) {
        for (final s in _steps) {
          s.controller.dispose();
        }
        _steps
          ..clear()
          ..addAll(steps.map((s) => _StepDraft(text: '$s')));
      }
      // Ingredientes sugeridos: se matchean contra insumos reales (costeable).
      final suggested = (data['ingredients'] as List?) ?? const [];
      for (final raw in suggested) {
        if (raw is! Map) continue;
        final name = ('${raw['name'] ?? ''}').trim().toLowerCase();
        if (name.isEmpty) continue;
        final qty = (raw['quantity'] as num?)?.toDouble() ?? 1;
        final match = _available.firstWhere(
          (i) =>
              i.name.toLowerCase() == name ||
              i.name.toLowerCase().contains(name) ||
              name.contains(i.name.toLowerCase()),
          orElse: () => _sentinel,
        );
        if (identical(match, _sentinel)) continue;
        if (_lines.any((l) => l.ingredient.uuid == match.uuid)) continue;
        _lines.add(_RecipeLine(match, qty <= 0 ? 1 : qty));
      }
    });
  }

  static final Ingredient _sentinel = Ingredient(uuid: '__none__', name: '');

  /// Modo EDICIÓN: precarga todos los campos de una receta existente.
  void _applyEditing(Recipe r) {
    setState(() {
      _nameCtrl.text = r.productName;
      _priceCtrl.text = r.salePrice.round().toString();
      _categoryCtrl.text = r.category;
      _emoji = r.emoji ?? _emoji;
      _photoUrl = (r.photoUrl?.isNotEmpty ?? false) ? r.photoUrl : null;
      _yieldCtrl.text = r.recipeYield;
      _timeCtrl.text = _digits(r.prepTime);
      for (final s in _steps) {
        s.controller.dispose();
      }
      _steps
        ..clear()
        ..addAll(r.prepSteps.map((m) => _StepDraft(text: '${m['text'] ?? ''}')
          ..photoUrl = (m['photo_url'] as String?)?.isNotEmpty ?? false
              ? m['photo_url'] as String
              : null));
      _lines.clear();
      for (final ing in r.ingredients) {
        final live = _available.firstWhere(
          (i) => i.uuid == ing.ingredientUuid,
          orElse: () => _sentinel,
        );
        final ingredient = identical(live, _sentinel)
            ? Ingredient(
                uuid: ing.ingredientUuid,
                name: ing.productName,
                unitCost: ing.unitCost)
            : live;
        _lines.add(_RecipeLine(ingredient, ing.quantity));
      }
    });
  }

  // ── Asistente IA ─────────────────────────────────────────────────────────
  Map<String, dynamic> _currentRecipeMap() => {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'yield': _yieldCtrl.text.trim(),
        'prep_time': _normalizedTime(),
        'ingredients': _lines
            .map((l) => {
                  'name': l.ingredient.name,
                  'quantity': l.quantity,
                  'unit': l.ingredient.unit,
                })
            .toList(),
        'steps': _steps
            .map((s) => s.controller.text.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      };

  Future<void> _askAI(String instructions) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Escriba el nombre del plato para que la IA ayude.',
          color: AppTheme.warning);
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final result = await _api.recipeAssist(
        name: name,
        instructions: instructions,
        current: _currentRecipeMap(),
      );
      if (!mounted) return;
      _applyInitial(result);
      _instructionsCtrl.clear();
      _snack('La IA actualizó el plato. Revíselo y ajuste lo que quiera.',
          color: AppTheme.success);
    } on AppError catch (e) {
      _snack(e.message, color: AppTheme.error);
    } catch (_) {
      _snack('La IA no pudo ayudar ahora. Intente de nuevo.',
          color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  // ── IA: proponer SOLO los pasos ───────────────────────────────────────────
  // A diferencia del asistente global (que regenera todo el plato vía
  // `_applyInitial`), esto aplica ÚNICAMENTE los pasos del resultado: conserva
  // insumos, precio, porciones, nombre y descripción ya ingresados. Los pasos
  // que el tendero ya escribió se mantienen; solo se descartan los vacíos.
  Future<void> _suggestSteps() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Escriba el nombre del plato para que la IA proponga los pasos.',
          color: AppTheme.warning);
      return;
    }
    setState(() => _aiBusy = true);
    try {
      final result = await _api.recipeAssist(
        name: name,
        instructions: 'Propón solo los pasos de preparación. '
            'No cambies los ingredientes, el precio ni las porciones.',
        current: _currentRecipeMap(),
      );
      if (!mounted) return;
      final proposed = ((result['steps'] as List?) ?? const [])
          .map((s) => '$s'.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (proposed.isEmpty) {
        _snack('La IA no propuso pasos. Intente de nuevo.',
            color: AppTheme.warning);
        return;
      }
      setState(() {
        // Conserva los pasos con contenido; solo descarta los placeholders vacíos.
        _steps.removeWhere((s) {
          final blank = s.controller.text.trim().isEmpty &&
              (s.photoUrl?.isEmpty ?? true);
          if (blank) s.controller.dispose();
          return blank;
        });
        _steps.addAll(proposed.map((t) => _StepDraft(text: t)));
      });
      _snack('La IA propuso los pasos. Revíselos, edítelos o reordénelos.',
          color: AppTheme.success);
    } on AppError catch (e) {
      _snack(e.message, color: AppTheme.error);
    } catch (_) {
      _snack('La IA no pudo proponer los pasos ahora. Intente de nuevo.',
          color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _openAiSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUI.radius)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppUI.s16,
          right: AppUI.s16,
          top: AppUI.s16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppUI.s16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SheetHandle(),
          const Row(children: [
            Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Que la IA me ayude', style: AppUI.title)),
          ]),
          const SizedBox(height: AppUI.s8),
          const Text(
            'Escriba el nombre del plato arriba y la IA propone ingredientes, '
            'pasos, porciones y tiempo. Usted revisa y corrige; nada se guarda '
            'hasta que toque Guardar.',
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: AppUI.s16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () {
                Navigator.of(ctx).pop();
                _askAI('');
              },
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Proponer ingredientes y pasos'),
            ),
          ),
          const SizedBox(height: AppUI.s16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('¿Ya tiene algo y quiere ajustarlo?',
                style: AppUI.sectionLabel),
          ),
          const SizedBox(height: AppUI.s8),
          Wrap(spacing: AppUI.s8, runSpacing: AppUI.s8, children: [
            for (final chip in const [
              'Más económica',
              'Sin lácteos',
              'Para más personas',
            ])
              ActionChip(
                label: Text(chip),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _askAI(chip);
                },
              ),
          ]),
        ]),
      ),
    );
  }

  // ── Foto del plato ─────────────────────────────────────────────────────
  Future<void> _generatePhoto() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Escriba el nombre del plato primero.', color: AppTheme.warning);
      return;
    }
    // Pregunta presentación (estilo + acompañamientos + cuáles van aparte) para
    // que la muestra IA salga realista. null = el tendero canceló. Spec 043/065.
    final presentation = await _askPresentation();
    if (!mounted || presentation == null) return;
    setState(() {
      _aiBusy = true;
      _photoBusy = true;
    });
    try {
      final url = await _api.generateMenuImage(
        name: name,
        category: _categoryCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        presentation: presentation,
      );
      if (!mounted) return;
      if (url.isEmpty) {
        _snack('La IA no devolvió una foto. Intente de nuevo.',
            color: AppTheme.warning);
      } else {
        setState(() {
          _photoUrl = url;
          _localPhoto = null;
        });
      }
    } on AppError catch (e) {
      _snack(e.message, color: AppTheme.error);
    } catch (_) {
      _snack('No pudimos generar la foto.', color: AppTheme.error);
    } finally {
      if (mounted) {
        setState(() {
          _aiBusy = false;
          _photoBusy = false;
        });
      }
    }
  }

  /// Hoja de presentación (opcional): estilo + acompañamientos + cuáles van en
  /// plato APARTE, para que la muestra IA salga realista. Devuelve la presentación
  /// compuesta, '' si la omite, o null si cancela. Portado del flujo de carta. Spec 043.
  Future<String?> _askPresentation() async {
    final detailCtrl = TextEditingController(text: _portionCtrl.text.trim());
    final customCtrl = TextEditingController();
    const styles = ['En plato', 'Para llevar', 'En vaso', 'En bandeja'];
    const defaultSides = [
      'Sopa', 'Arroz', 'Plátano maduro', 'Papa a la francesa',
      'Ensalada', 'Aguacate', 'Arepa', 'Frijoles', 'Jugo',
    ];
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList('custom_sides') ?? <String>[];
    final sides = <String>[...defaultSides, ...custom];
    String style = '';
    final selectedSides = <String>{};
    final apartSides = <String>{};

    Future<void> addCustom(StateSetter setSheet) async {
      final v = customCtrl.text.trim();
      if (v.isEmpty) return;
      final exists = sides.any((s) => s.toLowerCase() == v.toLowerCase());
      setSheet(() {
        if (!exists) {
          sides.add(v);
          custom.add(v);
          prefs.setStringList('custom_sides', custom);
        }
        selectedSides.add(exists ? sides.firstWhere((s) => s.toLowerCase() == v.toLowerCase()) : v);
        customCtrl.clear();
      });
    }

    if (!mounted) return null;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('¿Cómo se sirve el plato? (opcional)', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Entre más detalle, más parecida queda la muestra.', style: TextStyle(fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: styles.map((c) => ChoiceChip(
                label: Text(c, style: const TextStyle(fontSize: 15)),
                selected: style == c,
                selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                onSelected: (_) => setSheet(() => style = style == c ? '' : c),
              )).toList()),
              const SizedBox(height: 18),
              const Text('¿Con qué acompañamientos?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Escoja los que trae el plato.', style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: sides.map((c) => FilterChip(
                label: Text(c, style: const TextStyle(fontSize: 15)),
                selected: selectedSides.contains(c),
                selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                checkmarkColor: AppTheme.primary,
                onSelected: (sel) => setSheet(() {
                  if (sel) {
                    selectedSides.add(c);
                  } else {
                    selectedSides.remove(c);
                    apartSides.remove(c);
                  }
                }),
              )).toList()),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  key: const Key('custom_side_field'),
                  controller: customCtrl,
                  style: const TextStyle(fontSize: 15),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(isDense: true, hintText: 'Agregar otro (ej: chicharrón)'),
                  onSubmitted: (_) => addCustom(setSheet),
                )),
                const SizedBox(width: 8),
                TextButton.icon(key: const Key('add_custom_side'), onPressed: () => addCustom(setSheet), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Agregar')),
              ]),
              if (selectedSides.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('¿Alguno va en plato aparte?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('Toque los que NO van sobre el plato principal (ej: sopa, jugo).', style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: selectedSides.map((c) => FilterChip(
                  label: Text(c, style: const TextStyle(fontSize: 15)),
                  selected: apartSides.contains(c),
                  avatar: apartSides.contains(c) ? const Icon(Icons.call_split_rounded, size: 16, color: AppTheme.primary) : null,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                  showCheckmark: false,
                  onSelected: (sel) => setSheet(() => sel ? apartSides.add(c) : apartSides.remove(c)),
                )).toList()),
              ],
              const SizedBox(height: 16),
              TextField(controller: detailCtrl, style: const TextStyle(fontSize: 16), decoration: const InputDecoration(hintText: 'Otro detalle (ej: en hoja de plátano)')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextButton(onPressed: () => Navigator.of(ctx).pop(''), child: const Text('Omitir', style: TextStyle(fontSize: 16)))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(_composePresentation(style, selectedSides, apartSides, detailCtrl.text.trim())),
                  child: const Text('Crear foto', style: TextStyle(fontSize: 16)),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
    detailCtrl.dispose();
    customCtrl.dispose();
    return result;
  }

  /// Compone la presentación para el prompt de IA: estilo + acompañamientos
  /// (en el mismo plato vs aparte) + detalle libre. Spec 043.
  String _composePresentation(String style, Set<String> sides, Set<String> apart, String extra) {
    final parts = <String>[];
    if (style.isNotEmpty) parts.add(style);
    final enPlato = sides.where((s) => !apart.contains(s)).map((s) => s.toLowerCase()).toList();
    final aparte = sides.where((s) => apart.contains(s)).map((s) => s.toLowerCase()).toList();
    if (enPlato.isNotEmpty) parts.add('con ${enPlato.join(', ')} en el mismo plato');
    if (aparte.isNotEmpty) parts.add('${aparte.join(', ')} en plato aparte');
    if (extra.isNotEmpty) parts.add(extra);
    return parts.join(', ');
  }

  /// Genera la descripción del plato con IA (nombre + categoría) y la precarga en
  /// el campo para que el tendero la edite. Spec 043.
  Future<void> _generateDescription() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      _snack('Escriba el nombre del plato primero.', color: AppTheme.warning);
      return;
    }
    setState(() => _generatingDesc = true);
    try {
      final desc = await _api.generateMenuDescription(name: name, category: _categoryCtrl.text.trim());
      if (!mounted) return;
      if (desc.isNotEmpty) {
        _descCtrl.text = desc;
      } else {
        _snack('No pudimos generar la descripción. Intente de nuevo.', color: AppTheme.error);
      }
    } on AppError catch (e) {
      _snack(e.message, color: AppTheme.error);
    } catch (_) {
      _snack('No pudimos generar la descripción. Intente de nuevo.', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _generatingDesc = false);
    }
  }

  Future<void> _uploadOwnPhoto() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (photo == null || !mounted) return;
    setState(() {
      _aiBusy = true;
      _photoBusy = true;
    });
    try {
      final bytes = await photo.readAsBytes();
      final url = await _api.enhanceMenuImage(
        imageBytes: bytes,
        name: _nameCtrl.text.trim().isEmpty ? 'plato' : _nameCtrl.text.trim(),
        category: _categoryCtrl.text.trim(),
        mimeType: photo.mimeType ?? 'image/jpeg',
        filename: photo.name.isNotEmpty ? photo.name : 'plato.jpg',
      );
      if (!mounted) return;
      if (url.isEmpty) {
        _snack('No pudimos mejorar la foto.', color: AppTheme.warning);
      } else {
        setState(() {
          _photoUrl = url;
          _localPhoto = null;
        });
      }
    } on AppError catch (e) {
      _snack(e.message, color: AppTheme.error);
    } catch (_) {
      _snack('No pudimos subir la foto.', color: AppTheme.error);
    } finally {
      if (mounted) {
        setState(() {
          _aiBusy = false;
          _photoBusy = false;
        });
      }
    }
  }

  // ── Ingredientes: selector Spotlight ───────────────────────────────────
  Future<void> _spotlightPick() async {
    HapticFeedback.lightImpact();
    final used = _lines.map((l) => l.ingredient.uuid).toSet();
    final pool = _available.where((i) => !used.contains(i.uuid)).toList();
    // NUNCA es un callejón sin salida: aunque ya agregó todos los insumos
    // existentes (pool vacío), la hoja siempre ofrece "Crear insumo nuevo".
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUI.radius)),
      ),
      builder: (ctx) => _SpotlightSheet(pool: pool),
    );
    if (!mounted || result == null) return;
    if (result is Ingredient) {
      setState(() => _lines.add(_RecipeLine(result)));
    } else if (result is _CreateNewIngredient) {
      // No bloqueante: el tendero recordó un insumo mientras pensaba la
      // receta → lo crea aquí mismo y queda agregado al plato.
      await _createIngredientInline(prefillName: result.query);
    }
  }

  /// Crea un insumo SIN salir del Studio (hoja rápida) y lo agrega al plato.
  /// Reusa POST /ingredients; el costeo sigue derivándose igual.
  Future<void> _createIngredientInline({String prefillName = ''}) async {
    final data = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUI.radius)),
      ),
      builder: (ctx) => _CreateIngredientSheet(prefillName: prefillName),
    );
    if (data == null || !mounted) return;
    try {
      final created = await _api.createIngredient({
        'name': data['name'],
        'unit': data['unit'],
        'unit_cost': data['unit_cost'],
        'stock': 0,
        'min_stock': 0,
      });
      final ing = Ingredient.fromJson(created);
      if (!mounted) return;
      setState(() {
        _available.add(ing);
        if (!_lines.any((l) => l.ingredient.uuid == ing.uuid)) {
          _lines.add(_RecipeLine(ing));
        }
      });
      _snack('Insumo "${ing.name}" creado y agregado al plato.',
          color: AppTheme.success);
    } on AppError catch (e) {
      _snack(e.message, color: AppTheme.error);
    } catch (_) {
      _snack('No pudimos crear el insumo. Intente de nuevo.',
          color: AppTheme.error);
    }
  }

  void _removeLine(_RecipeLine line) {
    setState(() {
      _lines.remove(line);
      line.qtyCtrl.dispose();
    });
  }

  void _bumpQty(_RecipeLine line, double delta) {
    final next = (line.quantity + delta);
    if (next < 0) return;
    setState(() {
      line.quantity = next;
      line.qtyCtrl.text = _fmtQty(next);
    });
  }

  // Unidad corta para la fila (unidad→'u'; el resto tal cual: g, kg, ml, l).
  String _unitShort(String unit) => unit == 'unidad' ? 'u' : unit;

  /// Atajos de medida caseros (½ libra, 1 taza, 3 dientes…) que convierten a la
  /// unidad base del insumo y SUMAN a la cantidad. Resuelve "no sé cómo registrar
  /// media libra o 3 dientes" sin que el tendero calcule. Spec 078 #4.
  void _showQtyPresets(_RecipeLine line) {
    final presets = quantityPresetsForUnit(line.ingredient.unit);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('¿Cuánto de ${line.ingredient.name}?',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
                'Toque una medida y se suma. Se costea en ${line.ingredient.unitLabel.toLowerCase()}.',
                style: AppUI.bodySoft),
            const SizedBox(height: 14),
            if (presets.isEmpty)
              Text('Escriba la cantidad directamente en ${line.ingredient.unitLabel.toLowerCase()}.',
                  style: AppUI.bodySoft)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets
                    .map((p) => ActionChip(
                          label: Text(p.label, style: const TextStyle(fontSize: 16)),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _bumpQty(line, p.amount);
                            setSheet(() {});
                          },
                        ))
                    .toList(),
              ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Cantidad: ${_fmtQty(line.quantity)} ${_unitShort(line.ingredient.unit)}',
                  style: AppUI.bodyStrong),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Listo', style: TextStyle(fontSize: 16)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Corrige el COSTO UNITARIO del insumo (ej. Agua quedó en $6 por error). Lo
  /// persiste en el inventario (PATCH /ingredients) y recalcula el costo del
  /// plato. No toca la fórmula de costeo (Σ insumo·cantidad). Spec 078.
  Future<void> _editUnitCost(_RecipeLine line) async {
    if (line.ingredient.uuid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este insumo no se puede editar desde aquí.')));
      return;
    }
    final cur = line.ingredient.unitCost;
    final ctrl = TextEditingController(
        text: cur == cur.roundToDouble() ? cur.round().toString() : cur.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        // scrollable: con el teclado abierto el diálogo (título + ayuda + campo
        // + acciones) se desbordaba hacia arriba y se cortaba. scrollable hace
        // que el contenido se desplace dentro del diálogo en vez de cortarse.
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Costo de ${line.ingredient.name}', style: const TextStyle(fontSize: 19)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Costo por ${line.ingredient.unitLabel}. Se corrige también en su inventario.',
              style: AppUI.bodySoft),
          const SizedBox(height: AppUI.s12),
          TextField(
            key: const Key('unit_cost_field'),
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '\$ ', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final clean = ctrl.text
                  .replaceAll(RegExp(r'[^0-9,.]'), '')
                  .replaceAll('.', '')
                  .replaceAll(',', '.');
              final v = double.tryParse(clean);
              Navigator.of(ctx).pop((v != null && v >= 0) ? v : null);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _api.updateIngredient(line.ingredient.uuid, {'unit_cost': result});
      if (!mounted) return;
      setState(() => line.ingredient = line.ingredient.copyWith(unitCost: result));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Costo de ${line.ingredient.name} actualizado.'),
          backgroundColor: AppTheme.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppError ? e.message : 'No se pudo actualizar el costo.'),
          backgroundColor: AppTheme.error));
    }
  }

  // ── Pasos ───────────────────────────────────────────────────────────────
  Future<void> _attachStepPhoto(_StepDraft step) async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (photo == null || !mounted) return;
    setState(() => _aiBusy = true);
    try {
      final bytes = await photo.readAsBytes();
      final url = await _api.enhanceMenuImage(
        imageBytes: bytes,
        name: 'paso',
        mimeType: photo.mimeType ?? 'image/jpeg',
        filename: photo.name.isNotEmpty ? photo.name : 'paso.jpg',
      );
      if (!mounted) return;
      if (url.isNotEmpty) setState(() => step.photoUrl = url);
    } catch (_) {
      _snack('No pudimos adjuntar la foto del paso.', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  // ── Guardar (contrato intacto + campos nuevos) ─────────────────────────
  Future<void> _save() async {
    if (!_canSave) {
      _snack(_missingText, color: AppTheme.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        if (_linkProductId != null && _linkProductId!.isNotEmpty)
          'link_product_id': _linkProductId,
        'product_name': _nameCtrl.text.trim(),
        'sale_price': _salePrice.round(),
        'category': _categoryCtrl.text.trim(),
        'emoji': _emoji,
        if (_photoUrl != null && _photoUrl!.isNotEmpty) 'photo_url': _photoUrl,
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        if (_portionCtrl.text.trim().isNotEmpty)
          'portion': _portionCtrl.text.trim(),
        'yield': _yieldCtrl.text.trim(),
        'prep_time': _normalizedTime(),
        'prep_steps': _steps
            .where((s) => s.controller.text.trim().isNotEmpty)
            .map((s) => {
                  'text': s.controller.text.trim(),
                  if (s.photoUrl != null) 'photo_url': s.photoUrl,
                })
            .toList(),
        'ingredients': _lines
            .map((l) =>
                {'ingredient_uuid': l.ingredient.uuid, 'quantity': l.quantity})
            .toList(),
      };

      final result = _isEdit
          ? await _api.updateRecipe(widget.editing!.uuid, payload)
          : await _api.createRecipe(payload);

      final productId = result['product_id'] as String?;
      if (_localPhoto != null && productId != null && productId.isNotEmpty) {
        try {
          await _api.uploadProductPhoto(productId, _localPhoto!);
        } catch (e, st) {
          developer.log('Foto del plato no subió (receta sí se guardó)',
              name: 'RecipeStudioScreen', error: e, stackTrace: st);
        }
      }
      final uuid = _isEdit
          ? widget.editing!.uuid
          : (result['id'] ?? result['uuid']) as String?;
      if (uuid != null && uuid.isNotEmpty) {
        try {
          await _api.fetchRecipeCost(uuid);
        } catch (_) {/* el costo local ya se mostró */}
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      // El ScaffoldMessenger es de nivel app: capturarlo antes de navegar evita
      // usar un context que se va a desmontar.
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      if (_isEdit) {
        // La edición siempre viene del listado: volver a él (se refresca solo).
        if (navigator.canPop()) navigator.pop(true);
      } else {
        // Tras crear, aterrizar SIEMPRE en el listado de recetas (no en el
        // Dashboard), venga del listado, del hub o de voz. Deja la pila como
        // Raíz → Listado, sin acumular el Studio ni duplicar pantallas.
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => RecipeListScreen(apiOverride: widget.api)),
          (r) => r.isFirst,
        );
      }
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Listo. "${_nameCtrl.text.trim()}" quedó en su menú con una '
          'ganancia de ${_money(_profit)} por plato.',
        ),
        backgroundColor: AppTheme.success,
      ));
    } on AppError catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.message, color: AppTheme.error);
      }
    } catch (e, st) {
      developer.log('Error al guardar receta (Studio)',
          name: 'RecipeStudioScreen', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _saving = false);
        _snack('No se pudo guardar el plato. Intente de nuevo.',
            color: AppTheme.error);
      }
    }
  }

  void _snack(String msg, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 14)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(_isEdit ? 'Editar plato' : 'Nuevo plato', style: AppUI.title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: AppUI.bodySoft),
          const SizedBox(height: AppUI.s12),
          GhostButton(
              icon: Icons.refresh_rounded,
              label: 'Reintentar',
              onPressed: _loadIngredients),
        ]),
      );
    }
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppUI.s16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(children: [
                _aiEntry(),
                const SizedBox(height: AppUI.s16),
                _section('1. El plato', _section1()),
                const SizedBox(height: AppUI.s16),
                _section('2. Ingredientes y costo', _section2()),
                const SizedBox(height: AppUI.s16),
                _section('3. Preparación (opcional)', _section3()),
                const SizedBox(height: AppUI.s24),
              ]),
            ),
          ),
        ),
      ),
      _stickyBottom(),
    ]);
  }

  /// Encabezado de sección + tarjeta blanca con el contenido.
  Widget _section(String title, Widget child) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: AppUI.s8),
        child: Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppUI.ink)),
      ),
      SoftCard(child: child),
    ]);
  }

  // ── Atajo de IA (un solo punto de entrada, opcional) ──────────────────────
  Widget _aiEntry() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _aiBusy ? null : _openAiSheet,
        borderRadius: BorderRadius.circular(AppUI.radius),
        child: Container(
          padding: const EdgeInsets.all(AppUI.s16),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppUI.radius),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
            const SizedBox(width: AppUI.s12),
            const Expanded(
              child: Text(
                'Que la IA me ayude — propone ingredientes y pasos. Usted revisa.',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ),
            if (_aiBusy)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.chevron_right_rounded, color: AppTheme.primary),
          ]),
        ),
      ),
    );
  }

  // ── Sección 1: el plato ───────────────────────────────────────────────────
  Widget _section1() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _field(_nameCtrl, 'Nombre del plato',
          example: 'Ej: Bandeja paisa',
          onChanged: (_) => setState(() {}),
          key: 'studio_name'),
      const SizedBox(height: AppUI.s16),
      _field(_priceCtrl, 'Precio de venta',
          example: 'Lo que le cobra al cliente. Ej: 18.000',
          keyboard: TextInputType.number,
          onChanged: (_) => setState(() {}),
          key: 'studio_price'),
      const SizedBox(height: AppUI.s16),
      _autocompleteField(_categoryCtrl, _categoryFocus, 'Categoría (opcional)',
          'Elija una o escriba la suya', _kCategorySuggestions),
      const SizedBox(height: AppUI.s16),
      _autocompleteField(_portionCtrl, _portionFocus, 'Presentación (opcional)',
          'Cómo se sirve. Elija o escriba', _kPresentationSuggestions),
      const SizedBox(height: AppUI.s16),
      _field(_descCtrl, 'Descripción (opcional)',
          example: 'Una frase apetitosa para el catálogo', maxLines: 2),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('studio_describe_ai'),
          onPressed: _generatingDesc ? null : _generateDescription,
          icon: _generatingDesc
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_rounded, size: 18),
          label: Text(_generatingDesc ? 'Generando…' : 'Generar descripción con IA'),
        ),
      ),
      const SizedBox(height: AppUI.s8),
      const Text('Foto del plato', style: AppUI.sectionLabel),
      const SizedBox(height: AppUI.s8),
      _photoBox(),
    ]);
  }

  /// Visor a pantalla completa con pinch-zoom — la imagen se ve ÍNTEGRA
  /// (BoxFit.contain) para verificar que no quedó recortada.
  void _openPhotoViewer(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppUI.s12),
        child: Stack(children: [
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Center(
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: Colors.white54)),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _photoBox() {
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 120,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppUI.pageBg,
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          border: Border.all(color: AppUI.border),
        ),
        child: _photoBusy
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: AppUI.s8),
                    Text('Preparando la foto… puede tardar unos segundos',
                        textAlign: TextAlign.center, style: AppUI.bodySoft),
                  ],
                ),
              )
            : hasPhoto
                // Image.network (no DecorationImage) para poder mostrar el
                // progreso de carga y un fallback claro si la URL falla — antes
                // se quedaba en blanco sin que el tendero supiera qué pasó.
                // Tocar la foto → verla completa y ampliable (el thumbnail usa
                // cover y recorta; el visor usa contain → se ve íntegra).
                ? GestureDetector(
                    onTap: () => _openPhotoViewer(_photoUrl!),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network(
                        _photoUrl!,
                        // contain (no cover): muestra el plato COMPLETO en la
                        // vista previa, sin recortar los bordes.
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: 120,
                        loadingBuilder: (ctx, child, progress) =>
                            progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                        errorBuilder: (ctx, err, st) => const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image_outlined,
                                  size: 28, color: AppUI.inkSoft),
                              SizedBox(height: 4),
                              Text('No se pudo cargar la foto. Intente de nuevo.',
                                  textAlign: TextAlign.center,
                                  style: AppUI.bodySoft),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(AppUI.radiusSm),
                          ),
                          child: const Icon(Icons.zoom_out_map_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ]),
                  )
                : const Center(
                    child: Icon(Icons.restaurant_rounded,
                        size: 32, color: AppUI.inkSoft)),
      ),
      if (hasPhoto && !_photoBusy)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Toque la foto para ampliarla.',
              style: TextStyle(fontSize: 12, color: AppUI.inkSoft)),
        ),
      const SizedBox(height: AppUI.s8),
      Wrap(spacing: AppUI.s8, runSpacing: AppUI.s8, children: [
        GhostButton(
            icon: Icons.photo_library_rounded,
            label: 'Tomar o subir mi foto',
            onPressed: _aiBusy ? null : _uploadOwnPhoto),
        GhostButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Crear foto con IA',
            onPressed: _aiBusy ? null : _generatePhoto),
      ]),
    ]);
  }

  // ── Sección 2: ingredientes y costo ───────────────────────────────────────
  Widget _section2() {
    final noInsumos = _available.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Agregue los insumos que ya registró en Inventario y la cantidad que '
        'usa. El costo se calcula solo. Toque el costo de un insumo para corregirlo.',
        style: AppUI.bodySoft,
      ),
      const SizedBox(height: AppUI.s12),
      if (noInsumos)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Aún no tiene insumos. Créelos aquí mismo cuando los recuerde — '
              'no tiene que salir del plato.',
              style: AppUI.bodySoft),
          const SizedBox(height: AppUI.s8),
          GhostButton(
              icon: Icons.add_rounded,
              label: 'Crear insumo',
              color: AppTheme.primary,
              onPressed: () => _createIngredientInline()),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.inventory_2_rounded,
                  size: 16, color: AppUI.inkSoft),
              label: const Text('Administrar en Inventario',
                  style: TextStyle(fontSize: 13, color: AppUI.inkSoft)),
              // PUSH (no pop): conserva el plato. Al volver, refresca insumos.
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const IngredientsScreen()));
                await _refreshAvailable();
              },
            ),
          ),
        ])
      else ...[
        // Encabezados de columna (se lee como receta).
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Expanded(child: Text('Insumo', style: AppUI.sectionLabel)),
            SizedBox(
                width: 116,
                child: Text('Cantidad',
                    textAlign: TextAlign.center, style: AppUI.sectionLabel)),
            SizedBox(
                width: 72,
                child: Text('Costo',
                    textAlign: TextAlign.right, style: AppUI.sectionLabel)),
            SizedBox(width: 36),
          ]),
        ),
        const SizedBox(height: AppUI.s8),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
                'Aún no agrega insumos. Toque "Agregar insumo" para escogerlos '
                'de su inventario.',
                style: AppUI.bodySoft),
          )
        else
          ..._lines.map(_ingredientRow),
        const SizedBox(height: AppUI.s8),
        GhostButton(
            icon: Icons.add_rounded,
            label: 'Agregar insumo',
            color: AppTheme.primary,
            onPressed: _spotlightPick),
      ],
      const SizedBox(height: AppUI.s16),
      _costRecap(),
    ]);
  }

  Widget _ingredientRow(_RecipeLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(line.ingredient.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppUI.bodyStrong),
        ),
        // Cantidad editable (decimales). El +/- usa un paso sensato según la
        // unidad (±50 g, ±0.25 kg…, no ±1 que para gramos no sirve) y debajo
        // muestra la unidad + "medidas" para convertir medidas caseras
        // (½ libra, 1 taza, 3 dientes…) sin que el tendero calcule. Spec 078 #4.
        SizedBox(
          width: 124,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _miniBtn(Icons.remove_rounded,
                  () => _bumpQty(line, -quantityStepForUnit(line.ingredient.unit))),
              SizedBox(
                width: 36,
                child: TextField(
                  controller: line.qtyCtrl,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: AppUI.tabularStrong,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    final q = double.tryParse(v.replaceAll(',', '.'));
                    if (q != null && q >= 0) setState(() => line.quantity = q);
                  },
                ),
              ),
              _miniBtn(Icons.add_rounded,
                  () => _bumpQty(line, quantityStepForUnit(line.ingredient.unit))),
            ]),
            InkWell(
              key: Key('qty_presets_${line.ingredient.uuid}'),
              onTap: () => _showQtyPresets(line),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_unitShort(line.ingredient.unit),
                      style: AppUI.bodySoft.copyWith(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text('medidas',
                      style: AppUI.bodySoft.copyWith(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        // Costo TOCABLE: corrige el costo unitario del insumo (ej. Agua quedó en $6).
        SizedBox(
          width: 80,
          child: InkWell(
            key: Key('edit_cost_${line.ingredient.uuid}'),
            onTap: () => _editUnitCost(line),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Flexible(
                  child: Text(_money(line.totalCost),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUI.tabularStrong.copyWith(color: AppTheme.primary)),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.edit_outlined, size: 13, color: AppTheme.primary),
              ]),
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon:
                const Icon(Icons.close_rounded, size: 18, color: AppUI.inkSoft),
            tooltip: 'Quitar',
            onPressed: () => _removeLine(line),
          ),
        ),
      ]),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppUI.radiusSm),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUI.radiusSm),
            border: Border.all(color: AppUI.border),
          ),
          child: Icon(icon, size: 15, color: AppUI.ink),
        ),
      );

  /// Recap de costo dentro de la sección (sólido, sin glass) + nota explicativa.
  Widget _costRecap() {
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppUI.pageBg,
        borderRadius: BorderRadius.circular(AppUI.radiusSm),
        border: Border.all(color: AppUI.border),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(
                _servings > 1
                    ? 'Le cuesta hacer $_servings porciones'
                    : 'Le cuesta',
                style: AppUI.bodySoft),
          ),
          const SizedBox(width: AppUI.s8),
          Text(_money(_totalCost), style: AppUI.tabularStrong),
        ]),
        if (_servings > 1) ...[
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Expanded(
                child: Text('Costo de cada porción', style: AppUI.bodySoft)),
            const SizedBox(width: AppUI.s8),
            Text(_money(_costPerServing), style: AppUI.tabularStrong),
          ]),
        ],
        const SizedBox(height: 4),
        Text(
            _servings > 1
                ? 'Puso las cantidades para $_servings porciones; el costo por '
                    'plato es el total ÷ $_servings.'
                : 'El costo se suma solo: cada insumo por la cantidad que usa.',
            style: const TextStyle(fontSize: 12, color: AppUI.inkSoft)),
      ]),
    );
  }

  // ── Sección 3: preparación (opcional) ─────────────────────────────────────
  Widget _section3() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Porciones y tiempo APILADOS (nunca 2 columnas a 360dp).
      _field(_yieldCtrl, 'Porciones',
          example: 'Cuántas salen. Ej: 10',
          keyboard: TextInputType.number,
          onChanged: (_) => setState(() {})),
      const SizedBox(height: AppUI.s16),
      _field(_timeCtrl, 'Tiempo de preparación (minutos)',
          example: 'Solo el número de minutos. Ej: 30',
          keyboard: TextInputType.number),
      const SizedBox(height: AppUI.s16),
      Row(children: [
        const Expanded(child: Text('Pasos', style: AppUI.sectionLabel)),
        GhostButton(
            key: const Key('ia_steps'),
            icon: Icons.auto_awesome_rounded,
            label: 'IA',
            color: AppTheme.primary,
            onPressed: _aiBusy ? null : _suggestSteps),
        const SizedBox(width: AppUI.s8),
        GhostButton(
            icon: Icons.add_rounded,
            label: 'Paso',
            onPressed:
                _aiBusy ? null : () => setState(() => _steps.add(_StepDraft()))),
      ]),
      const SizedBox(height: AppUI.s8),
      if (_steps.isEmpty)
        const Text('Escríbalos, o toque IA arriba para que la IA los proponga. '
            'Puede arrastrarlos para reordenar.', style: AppUI.bodySoft)
      else
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _steps.length,
          onReorder: (oldI, newI) => setState(() {
            if (newI > oldI) newI -= 1;
            final s = _steps.removeAt(oldI);
            _steps.insert(newI, s);
          }),
          itemBuilder: (ctx, i) => _stepRow(i),
        ),
    ]);
  }

  Widget _stepRow(int i) {
    final step = _steps[i];
    return Padding(
      key: ValueKey(step),
      padding: const EdgeInsets.only(bottom: AppUI.s8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ReorderableDragStartListener(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, right: 8),
            child: Column(children: [
              Text('${i + 1}', style: AppUI.tabularStrong),
              const SizedBox(height: 2),
              const Icon(Icons.drag_indicator_rounded,
                  size: 16, color: AppUI.inkSoft),
            ]),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _field(step.controller, 'Paso ${i + 1}',
                example: 'Qué se hace en este paso', maxLines: 2),
            if (step.photoUrl != null && step.photoUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppUI.radiusSm),
                  child: Image.network(step.photoUrl!,
                      height: 64, width: 64, fit: BoxFit.cover),
                ),
              ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.image_outlined, size: 18, color: AppUI.inkSoft),
          tooltip: 'Adjuntar foto',
          onPressed: _aiBusy ? null : () => _attachStepPhoto(step),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 18, color: AppUI.inkSoft),
          tooltip: 'Eliminar paso',
          onPressed: () => setState(() {
            _steps.removeAt(i).controller.dispose();
          }),
        ),
      ]),
    );
  }

  // ── Campo con LABEL FIJO + ejemplo de ayuda (no placeholder que se va) ─────
  InputDecoration _fieldDecoration(String label, String? example) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppUI.inkSoft, fontSize: 14),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: example,
        helperStyle: const TextStyle(color: AppUI.inkSoft, fontSize: 12),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: AppUI.pageBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppUI.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppUI.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      );

  Widget _field(TextEditingController c, String label,
      {String? example,
      TextInputType? keyboard,
      int maxLines = 1,
      ValueChanged<String>? onChanged,
      String? key}) {
    return TextField(
      key: key == null ? null : Key(key),
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 15, color: AppUI.ink),
      decoration: _fieldDecoration(label, example),
    );
  }

  // ── Campo con AUTOCOMPLETE de sugerencias (categorías / presentaciones) ────
  // Usa RawAutocomplete con MI controller (así el texto libre o elegido siempre
  // queda en el mismo lugar). El tendero puede elegir una sugerencia o escribir.
  Widget _autocompleteField(TextEditingController c, FocusNode f, String label,
      String example, List<String> options) {
    return RawAutocomplete<String>(
      textEditingController: c,
      focusNode: f,
      optionsBuilder: (TextEditingValue v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((o) => o.toLowerCase().contains(q));
      },
      fieldViewBuilder: (ctx, textCtrl, focusNode, onSubmit) => TextField(
        controller: textCtrl,
        focusNode: focusNode,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => onSubmit(),
        style: const TextStyle(fontSize: 15, color: AppUI.ink),
        decoration: _fieldDecoration(label, example),
      ),
      optionsViewBuilder: (ctx, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final o in opts)
                  ListTile(
                    dense: true,
                    title: Text(o, style: AppUI.bodyStrong),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Barra inferior fija: costo + precio + ganancia + Guardar ──────────────
  Widget _stickyBottom() {
    final profitColor = _profit >= 0 ? AppTheme.success : AppTheme.error;
    final perPlate = _servings > 1; // mostrar "x plato" cuando rinde varias
    return Container(
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppUI.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _recapCell(perPlate ? 'Costo x plato' : 'Costo',
                _money(_costPerServing), AppUI.ink),
            _recapCell('Precio', _money(_salePrice), AppUI.ink),
            _recapCell(perPlate ? 'Ganancia x plato' : 'Ganancia',
                _money(_profit), profitColor),
          ]),
          const SizedBox(height: AppUI.s8),
          if (!_canSave)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_missingText,
                  style: const TextStyle(fontSize: 12, color: AppTheme.warning)),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                disabledBackgroundColor: AppTheme.success.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUI.radiusSm)),
              ),
              onPressed: (_canSave && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text(_isEdit ? 'Guardar cambios' : 'Guardar plato'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _recapCell(String label, String value, Color color) => Expanded(
        child: Column(children: [
          Text(label, style: AppUI.sectionLabel),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      );
}

/// Manija superior estándar de los bottom sheets (UI normalizada).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s12),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppUI.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Hoja Spotlight: búsqueda rápida de insumos (reemplaza el dropdown infinito).
class _SpotlightSheet extends StatefulWidget {
  final List<Ingredient> pool;
  const _SpotlightSheet({required this.pool});

  @override
  State<_SpotlightSheet> createState() => _SpotlightSheetState();
}

class _SpotlightSheetState extends State<_SpotlightSheet> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.pool
        .where((i) => i.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: AppUI.s16,
          right: AppUI.s16,
          top: AppUI.s8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Escoja un insumo', style: AppUI.title),
        ),
        const SizedBox(height: AppUI.s12),
        TextField(
          key: const Key('spotlight_search'),
          controller: _searchCtrl,
          autofocus: true,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Buscar insumo…',
            prefixIcon: const Icon(Icons.search_rounded, color: AppUI.inkSoft),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppUI.radiusSm)),
          ),
        ),
        const SizedBox(height: AppUI.s8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final ing in results)
                ListTile(
                  dense: true,
                  title: Text(ing.name, style: AppUI.bodyStrong),
                  trailing: Text(
                      '\$${ing.unitCost.round()} / ${ing.unitLabel.toLowerCase()}',
                      style: AppUI.bodySoft),
                  onTap: () => Navigator.of(context).pop(ing),
                ),
              // Crear el insumo que el tendero está buscando, sin salir.
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline_rounded,
                    color: AppTheme.primary),
                title: Text(
                  _q.trim().isEmpty
                      ? 'Crear insumo nuevo'
                      : 'Crear "${_q.trim()}"',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppTheme.primary),
                ),
                onTap: () =>
                    Navigator.of(context).pop(_CreateNewIngredient(_q.trim())),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppUI.s8),
      ]),
    );
  }
}

/// Señal que devuelve el Spotlight cuando el tendero quiere CREAR un insumo
/// nuevo (en vez de escoger uno existente). `query` es lo que venía buscando.
class _CreateNewIngredient {
  final String query;
  const _CreateNewIngredient(this.query);
}

/// Hoja rápida para CREAR un insumo sin salir del Studio (no bloqueante).
/// Devuelve {name, unit, unit_cost} por Navigator.pop; el Studio hace el POST.
class _CreateIngredientSheet extends StatefulWidget {
  final String prefillName;
  const _CreateIngredientSheet({this.prefillName = ''});

  @override
  State<_CreateIngredientSheet> createState() => _CreateIngredientSheetState();
}

class _CreateIngredientSheetState extends State<_CreateIngredientSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.prefillName);
  final _costCtrl = TextEditingController();
  String _unit = 'unidad';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  bool get _valid {
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
    return _nameCtrl.text.trim().isNotEmpty && cost > 0;
  }

  // Mismo look que los campos del formulario principal (UI normalizada).
  InputDecoration _sheetField(String label, String helper, {String? prefixText}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppUI.inkSoft, fontSize: 14),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helper,
        helperStyle: const TextStyle(color: AppUI.inkSoft, fontSize: 12),
        prefixText: prefixText,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: AppUI.pageBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppUI.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppUI.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppUI.s16,
        right: AppUI.s16,
        top: AppUI.s8,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppUI.s16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Nuevo insumo', style: AppUI.title),
        ),
        const SizedBox(height: AppUI.s4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Quedará en su inventario y agregado a este plato.',
              style: AppUI.bodySoft),
        ),
        const SizedBox(height: AppUI.s16),
        TextField(
          controller: _nameCtrl,
          autofocus: widget.prefillName.isEmpty,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: _sheetField('Nombre del insumo', 'Ej: Arroz, Aceite, Carne'),
        ),
        const SizedBox(height: AppUI.s16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Unidad de medida', style: AppUI.sectionLabel),
        ),
        const SizedBox(height: AppUI.s8),
        Wrap(
          spacing: AppUI.s8,
          children: [
            for (final u in Ingredient.validUnits)
              ChoiceChip(
                label: Text(Ingredient.unitLabels[u] ?? u),
                selected: _unit == u,
                onSelected: (_) => setState(() => _unit = u),
                selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: _unit == u ? AppTheme.primary : AppUI.ink,
                  fontWeight: _unit == u ? FontWeight.w600 : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppUI.radiusSm),
                  side: BorderSide(
                      color: _unit == u ? AppTheme.primary : AppUI.border),
                ),
                backgroundColor: Colors.white,
              ),
          ],
        ),
        const SizedBox(height: AppUI.s16),
        TextField(
          controller: _costCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: _sheetField(
            'Costo por ${(Ingredient.unitLabels[_unit] ?? _unit).toLowerCase()}',
            'Lo que le cuesta a usted. Ej: 3.000',
            prefixText: '\$ ',
          ),
        ),
        const SizedBox(height: AppUI.s16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppUI.radiusSm)),
            ),
            onPressed: _valid
                ? () => Navigator.of(context).pop({
                      'name': _nameCtrl.text.trim(),
                      'unit': _unit,
                      'unit_cost':
                          double.parse(_costCtrl.text.replaceAll(',', '.')),
                    })
                : null,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Crear y agregar al plato'),
          ),
        ),
      ]),
    );
  }
}
