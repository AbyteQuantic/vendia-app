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
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../inventory/ingredients_screen.dart';

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// Una línea costeada: un insumo REAL (uuid + unitCost) y la cantidad que
/// consume el plato. El costo se deriva igual que siempre.
class _RecipeLine {
  final Ingredient ingredient;
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

  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _portionCtrl = TextEditingController();
  final _yieldCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
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
  double get _totalCost => _lines.fold(0.0, (s, l) => s + l.totalCost);
  double get _salePrice => _parsePrice(_priceCtrl.text);
  double get _profit => _salePrice - _totalCost;

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
      if ((data['name'] as String?)?.isNotEmpty ?? false) {
        _nameCtrl.text = data['name'] as String;
      }
      if ((data['description'] as String?)?.isNotEmpty ?? false) {
        _descCtrl.text = data['description'] as String;
      }
      if ((data['yield'] as String?)?.isNotEmpty ?? false) {
        _yieldCtrl.text = data['yield'] as String;
      }
      if ((data['prep_time'] as String?)?.isNotEmpty ?? false) {
        _timeCtrl.text = data['prep_time'] as String;
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
      _timeCtrl.text = r.prepTime;
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
        'prep_time': _timeCtrl.text.trim(),
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
    setState(() {
      _aiBusy = true;
      _photoBusy = true;
    });
    try {
      final url = await _api.generateMenuImage(
        name: name,
        category: _categoryCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        presentation: _portionCtrl.text.trim(),
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
        'prep_time': _timeCtrl.text.trim(),
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
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
      _field(_categoryCtrl, 'Categoría (opcional)',
          example: 'Ej: Almuerzos, Corrientazo'),
      const SizedBox(height: AppUI.s16),
      _field(_portionCtrl, 'Presentación (opcional)',
          example: 'Cómo se sirve. Ej: Plato hondo, arroz aparte'),
      const SizedBox(height: AppUI.s16),
      _field(_descCtrl, 'Descripción (opcional)',
          example: 'Una frase apetitosa para el catálogo', maxLines: 2),
      const SizedBox(height: AppUI.s16),
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
        'usa. El costo se calcula solo.',
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
        // Cantidad editable (decimales) con +/- de apoyo + la unidad real.
        SizedBox(
          width: 116,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _miniBtn(Icons.remove_rounded, () => _bumpQty(line, -1)),
            SizedBox(
              width: 40,
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
            _miniBtn(Icons.add_rounded, () => _bumpQty(line, 1)),
          ]),
        ),
        SizedBox(
          width: 72,
          child: Text(_money(line.totalCost),
              textAlign: TextAlign.right, style: AppUI.tabularStrong),
        ),
        SizedBox(
          width: 36,
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
          const Text('Le cuesta', style: AppUI.bodySoft),
          Text(_money(_totalCost), style: AppUI.tabularStrong),
        ]),
        const SizedBox(height: 4),
        const Text('El costo se suma solo: cada insumo por la cantidad que usa.',
            style: TextStyle(fontSize: 12, color: AppUI.inkSoft)),
      ]),
    );
  }

  // ── Sección 3: preparación (opcional) ─────────────────────────────────────
  Widget _section3() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Porciones y tiempo APILADOS (nunca 2 columnas a 360dp).
      _field(_yieldCtrl, 'Porciones', example: 'Cuántas salen. Ej: 10'),
      const SizedBox(height: AppUI.s16),
      _field(_timeCtrl, 'Tiempo de preparación', example: 'Ej: 30 minutos'),
      const SizedBox(height: AppUI.s16),
      Row(children: [
        const Expanded(child: Text('Pasos', style: AppUI.sectionLabel)),
        GhostButton(
            icon: Icons.add_rounded,
            label: 'Paso',
            onPressed: () => setState(() => _steps.add(_StepDraft()))),
      ]),
      const SizedBox(height: AppUI.s8),
      if (_steps.isEmpty)
        const Text('Escriba los pasos, o deje que la IA los proponga. '
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
      decoration: InputDecoration(
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
      ),
    );
  }

  // ── Barra inferior fija: costo + precio + ganancia + Guardar ──────────────
  Widget _stickyBottom() {
    final profitColor = _profit >= 0 ? AppTheme.success : AppTheme.error;
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
            _recapCell('Costo', _money(_totalCost), AppUI.ink),
            _recapCell('Precio', _money(_salePrice), AppUI.ink),
            _recapCell('Ganancia', _money(_profit), profitColor),
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
