// Spec: specs/065-recipe-studio/spec.md
//
// Recipe Studio — editor profesional "SaaS Professional Density" que reemplaza
// el wizard lineal de 3 pasos. Doble panel en web/tablet, una columna en móvil.
// REGLA DE ORO: NO toca la lógica de costeo — el costo se sigue derivando de
// `_RecipeLine.totalCost = unitCost·quantity` y la suma `_totalCost`, igual que
// el flujo viejo; el guardado usa el mismo contrato `createRecipe`.
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ingredient.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';

/// Una línea costeada de la receta: un insumo REAL (con uuid + unitCost) y la
/// cantidad que consume el plato. El costo se deriva igual que antes.
class _RecipeLine {
  final Ingredient ingredient;
  double quantity;
  _RecipeLine(this.ingredient, [this.quantity = 1]);
  double get totalCost => ingredient.unitCost * quantity;
}

/// Un paso de preparación (editor tipo Notion): texto + foto opcional.
class _StepDraft {
  final TextEditingController controller;
  String? photoUrl;
  _StepDraft({String text = ''})
      : controller = TextEditingController(text: text);
}

class RecipeStudioScreen extends StatefulWidget {
  /// Prefill opcional desde voz/IA: {name, description, yield, prep_time,
  /// ingredients:[{name,quantity,unit}], steps:[String]}.
  final Map<String, dynamic>? initial;
  final ApiService? api;

  const RecipeStudioScreen({super.key, this.initial, this.api});

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
  final String _emoji = '🍽️';

  final List<_RecipeLine> _lines = [];
  final List<_StepDraft> _steps = [];
  List<Ingredient> _available = [];

  String? _photoUrl; // foto en R2 (IA generada o mejorada)
  XFile? _localPhoto; // foto cruda elegida, se sube al guardar

  bool _loading = true;
  bool _saving = false;
  bool _aiBusy = false;
  String? _error;

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

  // ── Costeo (lógica intacta) ────────────────────────────────────────────
  double get _totalCost => _lines.fold(0.0, (s, l) => s + l.totalCost);
  double get _salePrice => _parsePrice(_priceCtrl.text);
  double get _marginPct =>
      _salePrice > 0 ? ((_salePrice - _totalCost) / _salePrice) * 100 : 0;

  double _parsePrice(String t) =>
      double.tryParse(t.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  String _money(double v) => '\$${v.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      )}';

  String _trimQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
      // Pasos sugeridos (texto libre): se cargan tal cual.
      final steps = (data['steps'] as List?) ?? const [];
      if (steps.isNotEmpty) {
        for (final s in _steps) {
          s.controller.dispose();
        }
        _steps
          ..clear()
          ..addAll(steps.map((s) => _StepDraft(text: '$s')));
      }
      // Ingredientes sugeridos: se MATCHEAN contra los insumos reales del
      // tenant (los únicos costeables, con uuid+unitCost). Los que no existen
      // como insumo no se pueden costear, así que se omiten del costeo.
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

  // ── Asistente IA (texto): completar / refinar ──────────────────────────
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

  Future<void> _askAI({required bool refine}) async {
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
        instructions: refine ? _instructionsCtrl.text.trim() : '',
        current: _currentRecipeMap(),
      );
      if (!mounted) return;
      _applyInitial(result);
      _instructionsCtrl.clear();
      _snack('La IA actualizó la receta. Revísela y edite lo que quiera.',
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

  // ── Foto del plato: generar con IA o limpiar la del usuario ────────────
  Future<void> _generatePhoto() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Escriba el nombre del plato primero.', color: AppTheme.warning);
      return;
    }
    setState(() => _aiBusy = true);
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
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _cleanPhoto() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (photo == null || !mounted) return;
    setState(() => _aiBusy = true);
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
      _snack('No pudimos mejorar la foto.', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  // ── Ingredientes: selector Spotlight ───────────────────────────────────
  Future<void> _spotlightPick() async {
    HapticFeedback.lightImpact();
    final used = _lines.map((l) => l.ingredient.uuid).toSet();
    final pool = _available.where((i) => !used.contains(i.uuid)).toList();
    if (pool.isEmpty) {
      _snack(
          _available.isEmpty
              ? 'Primero registre sus insumos en la pantalla de Insumos.'
              : 'Ya agregó todos sus insumos.',
          color: AppTheme.primary);
      return;
    }
    final picked = await showModalBottomSheet<Ingredient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUI.radius)),
      ),
      builder: (ctx) => _SpotlightSheet(pool: pool),
    );
    if (picked != null) {
      setState(() => _lines.add(_RecipeLine(picked)));
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
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('El nombre del plato es obligatorio.', color: AppTheme.warning);
      return;
    }
    if (_salePrice <= 0) {
      _snack('Indique el precio de venta.', color: AppTheme.warning);
      return;
    }
    if (_lines.isEmpty) {
      _snack('Agregue al menos un insumo para costear el plato.',
          color: AppTheme.warning);
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
        if (_yieldCtrl.text.trim().isNotEmpty) 'yield': _yieldCtrl.text.trim(),
        if (_timeCtrl.text.trim().isNotEmpty) 'prep_time': _timeCtrl.text.trim(),
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
      final created = await _api.createRecipe(payload);

      // Foto cruda sin mejorar → subir al producto recién creado (best-effort).
      final productId = created['product_id'] as String?;
      if (_localPhoto != null && productId != null && productId.isNotEmpty) {
        try {
          await _api.uploadProductPhoto(productId, _localPhoto!);
        } catch (e, st) {
          developer.log('Foto del plato no subió (receta sí se guardó)',
              name: 'RecipeStudioScreen', error: e, stackTrace: st);
        }
      }
      // Costo autoritativo (best-effort, no bloquea).
      final uuid = (created['id'] ?? created['uuid']) as String?;
      if (uuid != null && uuid.isNotEmpty) {
        try {
          await _api.fetchRecipeCost(uuid);
        } catch (_) {/* el costo local ya se mostró */}
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${_nameCtrl.text.trim()}" guardado en el menú'),
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
        _snack('No se pudo guardar la receta. Intente de nuevo.',
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
        title: const Text('Recipe Studio',
            style: AppUI.title, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: Icon(
                _saving ? Icons.hourglass_top_rounded : Icons.check_rounded,
                size: 18,
                color: AppTheme.success),
            label: const Text('Guardar',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success)),
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
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 900;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppUI.s16),
                child: _infoPanel(),
              ),
            ),
            const VerticalDivider(width: 1, color: AppUI.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppUI.s16),
                child: Column(children: [
                  _costSummary(),
                  const SizedBox(height: AppUI.s16),
                  _aiBar(),
                  const SizedBox(height: AppUI.s16),
                  _ingredientsTable(),
                  const SizedBox(height: AppUI.s16),
                  _stepsEditor(),
                ]),
              ),
            ),
          ],
        );
      }
      // Móvil 360dp: una columna apilada, resumen fijo arriba.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppUI.s16),
        child: Column(children: [
          _costSummary(),
          const SizedBox(height: AppUI.s16),
          _aiBar(),
          const SizedBox(height: AppUI.s16),
          _infoPanel(),
          const SizedBox(height: AppUI.s16),
          _ingredientsTable(),
          const SizedBox(height: AppUI.s16),
          _stepsEditor(),
          const SizedBox(height: AppUI.s24),
        ]),
      );
    });
  }

  // ── Panel: info técnica ──────────────────────────────────────────────────
  Widget _infoPanel() {
    return Container(
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: AppUI.borderedCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Información del plato', style: AppUI.sectionLabel),
        const SizedBox(height: AppUI.s12),
        _photoBox(),
        const SizedBox(height: AppUI.s12),
        _field(_nameCtrl, 'Nombre del plato', key: 'studio_name'),
        const SizedBox(height: AppUI.s8),
        _field(_priceCtrl, 'Precio de venta',
            keyboard: TextInputType.number,
            onChanged: (_) => setState(() {}),
            key: 'studio_price'),
        const SizedBox(height: AppUI.s8),
        Row(children: [
          Expanded(child: _field(_yieldCtrl, 'Rendimiento (ej: 10 porc.)')),
          const SizedBox(width: AppUI.s8),
          Expanded(child: _field(_timeCtrl, 'Tiempo (ej: 30 min)')),
        ]),
        const SizedBox(height: AppUI.s8),
        _field(_categoryCtrl, 'Categoría'),
        const SizedBox(height: AppUI.s8),
        _field(_portionCtrl, 'Presentación / porción'),
        const SizedBox(height: AppUI.s8),
        _field(_descCtrl, 'Descripción', maxLines: 2),
      ]),
    );
  }

  Widget _photoBox() {
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppUI.pageBg,
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          border: Border.all(color: AppUI.border),
          image: hasPhoto
              ? DecorationImage(
                  image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: hasPhoto
            ? null
            : const Center(
                child: Icon(Icons.restaurant_rounded,
                    size: 32, color: AppUI.inkSoft)),
      ),
      const SizedBox(height: AppUI.s8),
      Wrap(spacing: AppUI.s8, runSpacing: AppUI.s8, children: [
        GhostButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Foto con IA',
            onPressed: _aiBusy ? null : _generatePhoto),
        GhostButton(
            icon: Icons.cleaning_services_rounded,
            label: 'Limpiar mi foto',
            onPressed: _aiBusy ? null : _cleanPhoto),
      ]),
    ]);
  }

  Widget _field(TextEditingController c, String hint,
      {TextInputType? keyboard,
      int maxLines = 1,
      ValueChanged<String>? onChanged,
      String? key}) {
    return TextField(
      key: key == null ? null : Key(key),
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppUI.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppUI.inkSoft, fontSize: 14),
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
      ),
    );
  }

  // ── Card glass de costeo en vivo ─────────────────────────────────────────
  Widget _costSummary() {
    return GlassCard(
      child: Row(children: [
        _costCell('Costo', _money(_totalCost), AppTheme.error),
        _divider(),
        _costCell('Precio', _money(_salePrice), AppUI.ink),
        _divider(),
        _costCell(
          'Margen',
          '${_marginPct.toStringAsFixed(0)}%',
          _marginPct >= 0 ? AppTheme.success : AppTheme.error,
        ),
      ]),
    );
  }

  Widget _costCell(String label, String value, Color color) => Expanded(
        child: Column(children: [
          Text(label, style: AppUI.sectionLabel),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      );

  Widget _divider() =>
      Container(width: 1, height: 36, color: AppUI.hairline);

  // ── Barra de asistente IA ────────────────────────────────────────────────
  Widget _aiBar() {
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.borderedCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          const Text('Asistente IA', style: AppUI.sectionLabel),
          const Spacer(),
          if (_aiBusy)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: AppUI.s8),
        Wrap(spacing: AppUI.s8, runSpacing: AppUI.s8, children: [
          GhostButton(
              icon: Icons.auto_fix_high_rounded,
              label: 'Completar con IA',
              color: AppTheme.primary,
              onPressed: _aiBusy ? null : () => _askAI(refine: false)),
        ]),
        const SizedBox(height: AppUI.s8),
        Row(children: [
          Expanded(
            child: _field(_instructionsCtrl,
                'Indíquele a la IA: "más económica", "sin lácteos"…'),
          ),
          const SizedBox(width: AppUI.s8),
          GhostButton(
              icon: Icons.send_rounded,
              label: 'Refinar',
              color: AppTheme.primary,
              onPressed: _aiBusy ? null : () => _askAI(refine: true)),
        ]),
      ]),
    );
  }

  // ── Tabla de ingredientes de alta densidad ───────────────────────────────
  Widget _ingredientsTable() {
    return Container(
      decoration: AppUI.borderedCard(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(children: [
            const Expanded(
                child: Text('Ingredientes',
                    style: AppUI.sectionLabel,
                    overflow: TextOverflow.ellipsis)),
            GhostButton(
                icon: Icons.add_rounded,
                label: 'Agregar',
                onPressed: _spotlightPick),
          ]),
        ),
        const Divider(height: 1, color: AppUI.border),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aún no agrega insumos. Toque "Agregar".',
                style: AppUI.bodySoft),
          )
        else
          ..._lines.map(_ingredientRow),
      ]),
    );
  }

  Widget _ingredientRow(_RecipeLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppUI.hairline)),
      ),
      child: Row(children: [
        const Icon(Icons.circle, size: 6, color: AppUI.inkSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Text(line.ingredient.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppUI.bodyStrong),
        ),
        _stepper(line),
        SizedBox(
          width: 40,
          child: Text(line.ingredient.unitLabel.toLowerCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppUI.bodySoft),
        ),
        SizedBox(
          width: 72,
          child: Text(_money(line.totalCost),
              textAlign: TextAlign.right, style: AppUI.tabularStrong),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 16, color: AppUI.inkSoft),
          tooltip: 'Quitar',
          onPressed: () => setState(() => _lines.remove(line)),
        ),
      ]),
    );
  }

  Widget _stepper(_RecipeLine line) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _miniBtn(Icons.remove_rounded, () {
        if (line.quantity > 1) setState(() => line.quantity -= 1);
      }),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('×${_trimQty(line.quantity)}', style: AppUI.tabularStrong),
      ),
      _miniBtn(Icons.add_rounded, () => setState(() => line.quantity += 1)),
    ]);
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppUI.radiusSm),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUI.radiusSm),
            border: Border.all(color: AppUI.border),
          ),
          child: Icon(icon, size: 16, color: AppUI.ink),
        ),
      );

  // ── Editor de pasos tipo Notion (drag & drop) ────────────────────────────
  Widget _stepsEditor() {
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.borderedCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('Preparación',
                  style: AppUI.sectionLabel,
                  overflow: TextOverflow.ellipsis)),
          GhostButton(
              icon: Icons.add_rounded,
              label: 'Paso',
              onPressed: () => setState(() => _steps.add(_StepDraft()))),
        ]),
        const SizedBox(height: AppUI.s8),
        if (_steps.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Agregue los pasos de preparación. Puede arrastrarlos '
                'para reordenar.', style: AppUI.bodySoft),
          )
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
      ]),
    );
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
            _field(step.controller, 'Describa el paso ${i + 1}', maxLines: 2),
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
          top: AppUI.s16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (_, i) {
              final ing = results[i];
              return ListTile(
                dense: true,
                title: Text(ing.name, style: AppUI.bodyStrong),
                trailing: Text(
                    '\$${ing.unitCost.round()} / ${ing.unitLabel.toLowerCase()}',
                    style: AppUI.bodySoft),
                onTap: () => Navigator.of(context).pop(ing),
              );
            },
          ),
        ),
        const SizedBox(height: AppUI.s8),
      ]),
    );
  }
}
