// Spec: specs/067-planear-menu-ia-ux/spec.md
//
// "Planear menú" — arma el menú semanal del comercio. El link online refleja el
// menú del día vigente. Spec 067: normalizado al kit AppUI (como las hermanas
// del módulo Recetas) + dos ayudas contra la repetición de armar 7 días:
//   · "Sugerir con IA": el backend propone la semana con las recetas reales
//     (POST /menu-plan/suggest, stateless). Fusiona aditivo SOLO en días vacíos
//     y NUNCA auto-guarda — el tendero revisa y toca Guardar.
//   · "Copiar a otros días": replica los platos de un día a los que elija.
//
// Decisiones (plan 066): planned_qty es SOLO guía de preparación (no stock, no
// viaja al público). Diseñado y probado a 360dp (Art. I), copy en modo USTED.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Claves de día en el orden de presentación (lunes primero) y su etiqueta.
const _dayOrder = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const _dayNames = {
  'mon': 'Lunes',
  'tue': 'Martes',
  'wed': 'Miércoles',
  'thu': 'Jueves',
  'fri': 'Viernes',
  'sat': 'Sábado',
  'sun': 'Domingo',
};

/// Mínimo de recetas para que "Sugerir con IA" valga la pena (alineado con el
/// corte temprano del backend).
const _minRecipesForAI = 3;

/// Un plato planeado: la receta + cuántos preparar (guía interna).
class _PlanItem {
  final String recipeUuid;
  int plannedQty;
  _PlanItem(this.recipeUuid, this.plannedQty);
}

/// El plan de un día: habilitado + sus platos.
class _DayPlan {
  bool enabled;
  List<_PlanItem> items;
  _DayPlan({this.enabled = false, List<_PlanItem>? items})
      : items = items ?? [];
}

class MenuPlannerScreen extends StatefulWidget {
  final ApiService? api;
  const MenuPlannerScreen({super.key, this.api});

  @override
  State<MenuPlannerScreen> createState() => _MenuPlannerScreenState();
}

class _MenuPlannerScreenState extends State<MenuPlannerScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  bool _loading = true;
  bool _saving = false;
  bool _suggesting = false;
  String? _error;

  /// Recetas del comercio (para el selector). uuid → nombre/categoría.
  List<Map<String, dynamic>> _recipes = [];
  int _incompleteCount = 0; // platos sin receta (sin costo) → no plan­eables aún
  final Map<String, _DayPlan> _days = {
    for (final d in _dayOrder) d: _DayPlan(),
  };
  List<Map<String, dynamic>> _overrides = [];

  /// Días recién llenados por "Sugerir con IA" (para el badge "IA").
  final Set<String> _aiFilled = {};

  /// Sedes del comercio (Spec 066 por-sede). Vacío/1 = no se muestra selector;
  /// el plan es por defecto (branch_id=''). >1 → el tendero elige la sede.
  List<Map<String, dynamic>> _branches = [];
  String _selectedBranchId = '';
  String _storeSlug = '';

  bool get _multiBranch => _branches.length > 1;
  bool get _canSuggest => _recipes.length >= _minRecipesForAI;

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
      // Recetas, sedes y slug se cargan una vez; el plan/overrides dependen de
      // la sede seleccionada.
      final base = await Future.wait([
        _api.fetchRecipes(),
        _api.fetchBranches(),
        _api.fetchStoreConfig(),
      ]);
      _recipes = (base[0] as List).cast<Map<String, dynamic>>();
      _branches = (base[1] as List).cast<Map<String, dynamic>>();
      _storeSlug = ((base[2] as Map)['store_slug'] ?? '').toString();

      // El conteo de platos incompletos es SOLO para el aviso del picker — NO debe
      // bloquear ni romper la carga de recetas (si falla, el planeador igual sirve).
      // Best-effort, fuera del camino crítico. Spec 078.
      _api.fetchIncompleteMenuItems().then((inc) {
        if (mounted) setState(() => _incompleteCount = inc.length);
      }).catchError((_) {});

      final results = await Future.wait([
        _api.fetchMenuPlan(branchId: _selectedBranchId),
        _api.fetchMenuOverrides(branchId: _selectedBranchId),
      ]);
      final plan = results[0] as Map<String, dynamic>;
      _overrides = (results[1] as List).cast<Map<String, dynamic>>();
      _applyDays((plan['days'] as Map?)?.cast<String, dynamic>() ?? {});
      if (mounted) setState(() => _loading = false);
    } on AppError catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No pudimos cargar su menú. Intente de nuevo.';
        });
      }
    }
  }

  void _applyDays(Map<String, dynamic> days) {
    for (final key in _dayOrder) {
      final raw = days[key];
      if (raw is Map) {
        final items = ((raw['items'] as List?) ?? [])
            .whereType<Map>()
            .map((it) => _PlanItem(
                  (it['recipe_uuid'] ?? '').toString(),
                  ((it['planned_qty'] ?? 0) as num).toInt(),
                ))
            .where((it) => it.recipeUuid.isNotEmpty)
            .toList();
        _days[key] = _DayPlan(enabled: raw['enabled'] == true, items: items);
      } else {
        _days[key] = _DayPlan();
      }
    }
  }

  Map<String, dynamic> _serializeDays() {
    return {
      for (final key in _dayOrder)
        key: {
          'enabled': _days[key]!.enabled,
          'items': _days[key]!
              .items
              .map((it) => {
                    'recipe_uuid': it.recipeUuid,
                    'planned_qty': it.plannedQty,
                  })
              .toList(),
        },
    };
  }

  String _recipeName(String uuid) {
    final r = _recipes.firstWhere(
      (e) => (e['id'] ?? e['uuid']).toString() == uuid,
      orElse: () => const {},
    );
    final name = (r['product_name'] ?? r['name'] ?? '').toString();
    return name.isEmpty ? 'Receta' : name;
  }

  /// Cambia la sede seleccionada y recarga su plantilla + ajustes.
  Future<void> _switchBranch(String branchId) async {
    if (branchId == _selectedBranchId) return;
    setState(() {
      _selectedBranchId = branchId;
      _loading = true;
      _aiFilled.clear();
    });
    try {
      final results = await Future.wait([
        _api.fetchMenuPlan(branchId: branchId),
        _api.fetchMenuOverrides(branchId: branchId),
      ]);
      final plan = results[0] as Map<String, dynamic>;
      _overrides = (results[1] as List).cast<Map<String, dynamic>>();
      _applyDays((plan['days'] as Map?)?.cast<String, dynamic>() ?? {});
    } catch (_) {
      if (mounted) _snack('No pudimos cargar esa sede.', AppTheme.error);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// "Sugerir con IA": pide la propuesta semanal y la fusiona de forma ADITIVA
  /// (solo en días sin platos). Nunca pisa lo armado ni llama a _save: el
  /// tendero revisa y toca Guardar.
  Future<void> _suggest() async {
    if (!_canSuggest || _suggesting) return;
    setState(() => _suggesting = true);
    try {
      final res = await _api.suggestMenuPlan(branchId: _selectedBranchId);
      final days = (res['days'] as Map?)?.cast<String, dynamic>() ?? {};
      final filled = _mergeSuggestion(days);
      if (!mounted) return;
      setState(() {
        _aiFilled
          ..clear()
          ..addAll(filled);
        _suggesting = false;
      });
      if (filled.isEmpty) {
        _snack(
            'La IA no encontró días nuevos para llenar. Revise su semana o ajústela a mano.',
            AppTheme.primary);
      } else {
        HapticFeedback.lightImpact();
        _snack('Listo: revise la propuesta y toque Guardar para publicarla.',
            AppTheme.success);
      }
    } on AppError catch (e) {
      if (mounted) {
        setState(() => _suggesting = false);
        _snack(e.message, AppTheme.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _suggesting = false);
        _snack('No pudimos sugerir su menú. Arme su semana a mano o intente de nuevo.',
            AppTheme.error);
      }
    }
  }

  /// Fusiona la propuesta de la IA en `_days`. ADITIVO: solo días sin platos.
  /// Valida cada recipe_uuid contra las recetas reales (defensa en cliente
  /// además de la whitelist del backend). Devuelve los días efectivamente
  /// llenados.
  Set<String> _mergeSuggestion(Map<String, dynamic> days) {
    final allowed =
        _recipes.map((r) => (r['id'] ?? r['uuid']).toString()).toSet();
    final filled = <String>{};
    for (final key in _dayOrder) {
      final raw = days[key];
      if (raw is! Map) continue;
      if (_days[key]!.items.isNotEmpty) continue; // no pisar lo ya armado.
      final items = ((raw['items'] as List?) ?? [])
          .whereType<Map>()
          .map((it) => _PlanItem(
                (it['recipe_uuid'] ?? '').toString(),
                ((it['planned_qty'] ?? 0) as num).toInt(),
              ))
          .where((it) =>
              it.recipeUuid.isNotEmpty && allowed.contains(it.recipeUuid))
          .toList();
      if (items.isEmpty) continue;
      _days[key] = _DayPlan(enabled: true, items: items);
      filled.add(key);
    }
    return filled;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.saveMenuPlan(_serializeDays(), branchId: _selectedBranchId);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Menú guardado', style: TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();
    } on AppError catch (e) {
      if (mounted) _snack(e.message, AppTheme.error);
    } catch (_) {
      if (mounted) _snack('No pudimos guardar. Intente de nuevo.', AppTheme.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _editDay(String dayKey) async {
    final nonEmpty = {
      for (final k in _dayOrder)
        if (k != dayKey && _days[k]!.items.isNotEmpty) k,
    };
    final result = await showModalBottomSheet<_DayPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayEditorSheet(
        title: _dayNames[dayKey]!,
        dayKey: dayKey,
        plan: _days[dayKey]!,
        recipes: _recipes,
        incompleteCount: _incompleteCount,
        recipeName: _recipeName,
        nonEmptyDays: nonEmpty,
        onCopyToDays: (items, targetKeys) {
          setState(() {
            for (final k in targetKeys) {
              _days[k] = _DayPlan(
                enabled: true,
                items: items
                    .map((it) => _PlanItem(it.recipeUuid, it.plannedQty))
                    .toList(),
              );
              _aiFilled.remove(k);
            }
          });
        },
      ),
    );
    if (result != null) setState(() => _days[dayKey] = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Planear menú', style: AppUI.title),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: AppUI.s8),
              child: GhostButton(
                key: const Key('menu_planner_save'),
                icon: Icons.check_rounded,
                label: 'Guardar',
                color: AppTheme.primary,
                onPressed: _saving ? null : _save,
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _MessageState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  actionLabel: 'Reintentar',
                  onAction: _load,
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: AppUI.s12, left: AppUI.s4, right: AppUI.s4),
          child: Text(
            'Arme el menú de cada día. Prenda los días que abre y elija qué platos '
            'ofrece. Su link en línea mostrará solo el menú del día.',
            style: AppUI.bodySoft,
          ),
        ),
        // Spec 066 por-sede: solo aparece cuando el comercio tiene más de una
        // sede. Cada sede planea su menú y tiene su propio link en línea.
        if (_multiBranch) ...[
          _BranchSelector(
            branches: _branches,
            selectedId: _selectedBranchId,
            onChanged: _switchBranch,
          ),
          if (_selectedBranchId.isNotEmpty && _storeSlug.isNotEmpty)
            _BranchLinkCard(
              url: '${ApiConfig.publicCatalogUrlFor(_storeSlug)}?sede=$_selectedBranchId',
              onSnack: (m) => _snack(m, AppTheme.success),
            ),
          const SizedBox(height: AppUI.s12),
        ],
        _SuggestCard(
          enabled: _canSuggest,
          suggesting: _suggesting,
          onSuggest: _suggest,
        ),
        const SizedBox(height: AppUI.s16),
        const Padding(
          padding: EdgeInsets.only(left: AppUI.s4, bottom: AppUI.s8),
          child: Text('Menú de la semana', style: AppUI.sectionLabel),
        ),
        InsetGroupedList(
          children: [
            for (final key in _dayOrder)
              _DayRow(
                dayKey: key,
                name: _dayNames[key]!,
                plan: _days[key]!,
                aiFilled: _aiFilled.contains(key),
                onToggle: (v) => setState(() => _days[key]!.enabled = v),
                onTap: () => _editDay(key),
              ),
          ],
        ),
        const SizedBox(height: AppUI.s24),
        _OverridesSection(
          overrides: _overrides,
          recipes: _recipes,
          recipeName: _recipeName,
          api: _api,
          branchId: _selectedBranchId,
          onChanged: () async {
            try {
              final list =
                  await _api.fetchMenuOverrides(branchId: _selectedBranchId);
              if (mounted) {
                setState(() =>
                    _overrides = list.cast<Map<String, dynamic>>());
              }
            } catch (_) {/* la lista se refresca al reabrir */}
          },
        ),
      ],
    );
  }
}

/// Tarjeta de la acción inteligente "Sugerir con IA".
class _SuggestCard extends StatelessWidget {
  final bool enabled;
  final bool suggesting;
  final VoidCallback onSuggest;

  const _SuggestCard({
    required this.enabled,
    required this.suggesting,
    required this.onSuggest,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(AppUI.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: AppTheme.primary, size: 20),
              SizedBox(width: AppUI.s8),
              Expanded(
                child: Text('Arme su semana más rápido', style: AppUI.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: AppUI.s4),
          Text(
            enabled
                ? 'La IA propone un menú con sus recetas. Usted lo revisa y guarda; '
                    'no se publica nada hasta que toque Guardar.'
                : 'Con al menos $_minRecipesForAI recetas podemos proponerle el menú de la semana.',
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: AppUI.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: suggesting
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppUI.s8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: AppUI.s12),
                        Text('Armando su menú…', style: AppUI.bodySoft),
                      ],
                    ),
                  )
                : GhostButton(
                    key: const Key('menu_suggest_ai'),
                    icon: Icons.auto_awesome_rounded,
                    label: 'Sugerir con IA',
                    color: AppTheme.primary,
                    onPressed: enabled ? onSuggest : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un día dentro de la lista agrupada (InsetGroupedList).
class _DayRow extends StatelessWidget {
  final String dayKey;
  final String name;
  final _DayPlan plan;
  final bool aiFilled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _DayRow({
    required this.dayKey,
    required this.name,
    required this.plan,
    required this.aiFilled,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = plan.items.length;
    final totalDishes =
        plan.items.fold<int>(0, (sum, it) => sum + it.plannedQty);
    final subtitle = count == 0
        ? 'Sin platos asignados'
        : '$count receta${count == 1 ? '' : 's'}'
            '${totalDishes > 0 ? ' · $totalDishes por preparar' : ''}';

    return InkWell(
      key: Key('menu_day_$dayKey'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s8, AppUI.s12),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 20,
                color: plan.enabled ? AppTheme.primary : AppUI.inkSoft),
            const SizedBox(width: AppUI.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: AppUI.bodyStrong),
                      ),
                      const SizedBox(width: AppUI.s8),
                      MinimalBadge(
                        label: plan.enabled ? 'Abierto' : 'Cerrado',
                        color: plan.enabled ? AppTheme.success : AppUI.inkSoft,
                      ),
                      if (aiFilled) ...[
                        const SizedBox(width: AppUI.s4),
                        const MinimalBadge(label: 'IA', color: AppTheme.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppUI.bodySoft),
                ],
              ),
            ),
            Switch(
              key: Key('menu_day_switch_$dayKey'),
              value: plan.enabled,
              activeThumbColor: AppTheme.primary,
              onChanged: onToggle,
            ),
            const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Editor del plan de un día (o de un override): lista de recetas con su
/// cantidad guía, agregar y quitar. Devuelve un _DayPlan al cerrar con guardar.
/// Spec 067: si es un día de la plantilla (dayKey != null) ofrece "Copiar a
/// otros días".
class _DayEditorSheet extends StatefulWidget {
  final String title;
  final String? dayKey;
  final _DayPlan plan;
  final List<Map<String, dynamic>> recipes;
  final int incompleteCount;
  final String Function(String) recipeName;
  final Set<String> nonEmptyDays;
  final void Function(List<_PlanItem> items, List<String> targetKeys)?
      onCopyToDays;

  const _DayEditorSheet({
    required this.title,
    required this.plan,
    required this.recipes,
    required this.recipeName,
    this.incompleteCount = 0,
    this.dayKey,
    this.nonEmptyDays = const {},
    this.onCopyToDays,
  });

  @override
  State<_DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<_DayEditorSheet> {
  late final List<_PlanItem> _items = widget.plan.items
      .map((it) => _PlanItem(it.recipeUuid, it.plannedQty))
      .toList();

  bool get _canCopy =>
      widget.dayKey != null && widget.onCopyToDays != null && _items.isNotEmpty;

  Future<void> _addRecipe() async {
    final taken = _items.map((e) => e.recipeUuid).toSet();
    final available = widget.recipes
        .where((r) => !taken.contains((r['id'] ?? r['uuid']).toString()))
        .toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecipePickerSheet(
        recipes: available,
        incompleteCount: widget.incompleteCount,
      ),
    );
    if (picked != null) {
      setState(() => _items.add(_PlanItem(picked, 0)));
    }
  }

  /// Abre el selector de días destino para copiar este día.
  Future<void> _copyToOtherDays() async {
    final targets = _dayOrder.where((k) => k != widget.dayKey).toList();
    final selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Copiar a otros días', style: AppUI.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Estos platos se copiarán a los días que marque. Podrá ajustarlos luego.',
                  style: AppUI.bodySoft),
              const SizedBox(height: AppUI.s12),
              Wrap(
                spacing: AppUI.s8,
                runSpacing: AppUI.s8,
                children: [
                  for (final k in targets)
                    FilterChip(
                      key: Key('menu_copy_target_$k'),
                      label: Text(_dayNames[k]!),
                      selected: selected.contains(k),
                      onSelected: (v) => setLocal(() {
                        v ? selected.add(k) : selected.remove(k);
                      }),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('menu_copy_confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('Copiar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selected.isEmpty || !mounted) return;

    // Si algún destino ya tiene platos, confirmar el reemplazo (no perder
    // trabajo sin avisar).
    final overwrites = selected.where(widget.nonEmptyDays.contains).toList();
    if (overwrites.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reemplazar días con menú', style: AppUI.title),
          content: Text(
            'Estos días ya tienen platos y se reemplazarán: '
            '${overwrites.map((k) => _dayNames[k]!).join(', ')}. ¿Continuar?',
            style: AppUI.bodySoft,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('menu_copy_overwrite_confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    widget.onCopyToDays!(_items, selected.toList());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Copiado a ${selected.length} día(s)',
            style: const TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppUI.s8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppUI.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Menú del ${widget.title.toLowerCase()}',
                        style: AppUI.title),
                  ),
                  GhostButton(
                    key: const Key('menu_day_add_recipe'),
                    icon: Icons.add_rounded,
                    label: 'Agregar',
                    color: AppTheme.primary,
                    onPressed: widget.recipes.isEmpty ? null : _addRecipe,
                  ),
                ],
              ),
            ),
            if (_canCopy)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppUI.s12, bottom: AppUI.s4),
                  child: GhostButton(
                    key: const Key('menu_day_copy'),
                    icon: Icons.copy_all_rounded,
                    label: 'Copiar a otros días',
                    onPressed: _copyToOtherDays,
                  ),
                ),
              ),
            Flexible(
              child: _items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                      child: Text(
                        'Aún no hay platos para este día. Toque "Agregar" para '
                        'elegir de sus recetas.',
                        textAlign: TextAlign.center,
                        style: AppUI.bodySoft,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s4, AppUI.s8, AppUI.s8),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: AppUI.hairline),
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(widget.recipeName(it.recipeUuid),
                              style: AppUI.bodyStrong),
                          subtitle: _QtyStepper(
                            qty: it.plannedQty,
                            onChanged: (v) =>
                                setState(() => it.plannedQty = v),
                          ),
                          trailing: IconButton(
                            key: Key('menu_remove_$i'),
                            icon: Icon(Icons.delete_outline_rounded,
                                color: Colors.red.shade300),
                            onPressed: () =>
                                setState(() => _items.removeAt(i)),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s4, AppUI.s16, AppUI.s12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('menu_day_done'),
                  onPressed: () => Navigator.of(context).pop(
                    _DayPlan(enabled: widget.plan.enabled, items: _items),
                  ),
                  child: const Text('Listo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contador de cantidad guía (planned_qty). 0 = sin guía.
class _QtyStepper extends StatelessWidget {
  final int qty;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Preparar: ', style: AppUI.bodySoft),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 22),
          onPressed: qty > 0 ? () => onChanged(qty - 1) : null,
        ),
        Text(qty == 0 ? '—' : '$qty',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 22),
          onPressed: () => onChanged(qty + 1),
        ),
      ],
    );
  }
}

/// Selector tipo Spotlight de recetas existentes.
class _RecipePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> recipes;
  final int incompleteCount;
  const _RecipePickerSheet({required this.recipes, this.incompleteCount = 0});

  @override
  State<_RecipePickerSheet> createState() => _RecipePickerSheetState();
}

class _RecipePickerSheetState extends State<_RecipePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.recipes
        : widget.recipes
            .where((r) => (r['product_name'] ?? r['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(q))
            .toList();
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppUI.s12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppUI.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s8),
              child: TextField(
                key: const Key('recipe_picker_search'),
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Buscar receta…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
            // Informa por qué algunos platos NO aparecen: sin receta = sin costo,
            // no se pueden agregar al menú hasta completarlos. Spec 078.
            if (widget.incompleteCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppUI.s16, 0, AppUI.s16, AppUI.s8),
                child: Container(
                  padding: const EdgeInsets.all(AppUI.s12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
                    const SizedBox(width: AppUI.s8),
                    Expanded(
                      child: Text(
                        'Tiene ${widget.incompleteCount} plato(s) sin receta. No se pueden agregar al menú hasta completarlos: necesitan ingredientes para calcular el costo. Complételos en "Ver mis recetas".',
                        style: AppUI.bodySoft.copyWith(fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
              ),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No hay recetas para mostrar.',
                          style: AppUI.bodySoft),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        final uuid = (r['id'] ?? r['uuid']).toString();
                        return ListTile(
                          key: Key('recipe_pick_$i'),
                          leading: const Icon(Icons.restaurant_menu_rounded,
                              color: AppTheme.primary),
                          title: Text(
                              (r['product_name'] ?? r['name'] ?? 'Receta')
                                  .toString(),
                              style: AppUI.bodyStrong),
                          subtitle: (r['category'] ?? '').toString().isEmpty
                              ? null
                              : Text(r['category'].toString(),
                                  style: AppUI.bodySoft),
                          onTap: () => Navigator.of(context).pop(uuid),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sección de ajustes por fecha (overrides) — Fase 3.
class _OverridesSection extends StatelessWidget {
  final List<Map<String, dynamic>> overrides;
  final List<Map<String, dynamic>> recipes;
  final String Function(String) recipeName;
  final ApiService api;
  final String branchId;
  final Future<void> Function() onChanged;

  const _OverridesSection({
    required this.overrides,
    required this.recipes,
    required this.recipeName,
    required this.api,
    required this.branchId,
    required this.onChanged,
  });

  Future<void> _addOverride(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Elija la fecha a ajustar',
    );
    if (picked == null || !context.mounted) return;
    final dateStr =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

    final plan = _DayPlan(enabled: true);
    final result = await showModalBottomSheet<_DayPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayEditorSheet(
        title: dateStr,
        plan: plan,
        recipes: recipes,
        recipeName: recipeName,
      ),
    );
    if (result == null) return;
    try {
      await api.saveMenuOverride({
        'date': dateStr,
        'enabled': result.enabled,
        'items': result.items
            .map((it) => {
                  'recipe_uuid': it.recipeUuid,
                  'planned_qty': it.plannedQty,
                })
            .toList(),
      }, branchId: branchId);
      await onChanged();
    } catch (_) {/* el snackbar global cubre el error de red */}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Ajustes por fecha', style: AppUI.sectionLabel),
            ),
            GhostButton(
              key: const Key('menu_add_override'),
              icon: Icons.event_rounded,
              label: 'Ajustar fecha',
              color: AppTheme.primary,
              onPressed: () => _addOverride(context),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: AppUI.s4, top: AppUI.s4, bottom: AppUI.s8),
          child: Text(
            'Cambie el menú de un día puntual (un festivo, un evento) sin tocar '
            'su plantilla semanal.',
            style: AppUI.bodySoft,
          ),
        ),
        if (overrides.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppUI.s8, horizontal: AppUI.s4),
            child: Text('Sin ajustes próximos.', style: AppUI.bodySoft),
          )
        else
          InsetGroupedList(
            children: [
              for (final ov in overrides)
                ListTile(
                  key: Key('override_${ov['date']}'),
                  leading: const Icon(Icons.event_available_rounded,
                      color: AppTheme.primary),
                  title: Text(ov['date'].toString(), style: AppUI.bodyStrong),
                  subtitle: Text(
                      ov['enabled'] == true
                          ? '${((ov['items'] as List?) ?? []).length} plato(s)'
                          : 'Cerrado ese día',
                      style: AppUI.bodySoft),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.red.shade300),
                    onPressed: () async {
                      await api.deleteMenuOverride(ov['date'].toString(),
                          branchId: branchId);
                      await onChanged();
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Selector de sede (Spec 066 por-sede). Solo se monta con >1 sede.
class _BranchSelector extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  final String selectedId;
  final ValueChanged<String> onChanged;

  const _BranchSelector({
    required this.branches,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // "" = todas las sedes / menú por defecto del comercio.
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Menú general (todas las sedes)')),
      ...branches.map((b) => DropdownMenuItem(
            value: (b['id'] ?? '').toString(),
            child: Text((b['name'] ?? 'Sede').toString()),
          )),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s8),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: AppUI.s16, vertical: AppUI.s4),
        child: Row(
          children: [
            const Icon(Icons.store_mall_directory_rounded,
                color: AppTheme.primary, size: 20),
            const SizedBox(width: AppUI.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Planeando la sede', style: AppUI.sectionLabel),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('menu_branch_selector'),
                      isExpanded: true,
                      value: selectedId,
                      items: items,
                      onChanged: (v) => onChanged(v ?? ''),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta con el link en línea de la sede seleccionada, para compartir (AC-10).
class _BranchLinkCard extends StatelessWidget {
  final String url;
  final ValueChanged<String> onSnack;
  const _BranchLinkCard({required this.url, required this.onSnack});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s4, AppUI.s8),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: AppTheme.primary, size: 20),
          const SizedBox(width: AppUI.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Link de esta sede', style: AppUI.sectionLabel),
                Text(url.replaceFirst('https://', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.bodyStrong),
              ],
            ),
          ),
          IconButton(
            key: const Key('menu_branch_link_copy'),
            icon: const Icon(Icons.copy_rounded, size: 20, color: AppUI.inkSoft),
            tooltip: 'Copiar link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              onSnack('Link de la sede copiado');
            },
          ),
        ],
      ),
    );
  }
}

/// Estado de mensaje (error/vacío) calcado de recipe_list_screen.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  const _MessageState({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(icon, size: 56, color: AppUI.inkSoft),
        const SizedBox(height: AppUI.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(title, textAlign: TextAlign.center, style: AppUI.title),
        ),
        const SizedBox(height: AppUI.s24),
        Center(
          child: GhostButton(
            icon: Icons.refresh_rounded,
            label: actionLabel,
            color: AppTheme.primary,
            onPressed: onAction,
          ),
        ),
      ],
    );
  }
}
