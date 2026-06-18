// Spec: specs/066-planear-menu/spec.md
//
// "Planear menú" — arma el menú semanal del comercio. Reemplaza la tarjeta
// "Crear plato o receta" del hub (crear sigue disponible desde "Ver mis
// recetas", cámara y voz). El link online refleja el menú del día vigente.
//
// Decisiones (plan 066): planned_qty es SOLO guía de preparación (no stock, no
// viaja al público); el orden online es por categoría/nombre; ámbito MVP por
// tenant. Diseñado y probado a 360dp (Art. I), copy en modo USTED.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

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
  String? _error;

  /// Recetas del comercio (para el selector). uuid → nombre/categoría.
  List<Map<String, dynamic>> _recipes = [];
  final Map<String, _DayPlan> _days = {
    for (final d in _dayOrder) d: _DayPlan(),
  };
  List<Map<String, dynamic>> _overrides = [];

  /// Sedes del comercio (Spec 066 por-sede). Vacío/1 = no se muestra selector;
  /// el plan es por defecto (branch_id=''). >1 → el tendero elige la sede.
  List<Map<String, dynamic>> _branches = [];
  String _selectedBranchId = '';
  String _storeSlug = '';

  bool get _multiBranch => _branches.length > 1;

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
    final result = await showModalBottomSheet<_DayPlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayEditorSheet(
        title: _dayNames[dayKey]!,
        plan: _days[dayKey]!,
        recipes: _recipes,
        recipeName: _recipeName,
      ),
    );
    if (result != null) setState(() => _days[dayKey] = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Planear menú'),
        actions: [
          if (!_loading)
            TextButton(
              key: const Key('menu_planner_save'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 14, left: 4, right: 4),
          child: Text(
            'Arme el menú de cada día. Prenda los días que abre y elija qué platos '
            'ofrece. Su link en línea mostrará solo el menú del día.',
            style: TextStyle(fontSize: 14.5, color: Colors.black54, height: 1.3),
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
          const SizedBox(height: 6),
        ],
        for (final key in _dayOrder) ...[
          _DayCard(
            dayKey: key,
            name: _dayNames[key]!,
            plan: _days[key]!,
            recipeName: _recipeName,
            onToggle: (v) => setState(() => _days[key]!.enabled = v),
            onTap: () => _editDay(key),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
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

/// Tarjeta de un día en la lista semanal.
class _DayCard extends StatelessWidget {
  final String dayKey;
  final String name;
  final _DayPlan plan;
  final String Function(String) recipeName;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _DayCard({
    required this.dayKey,
    required this.name,
    required this.plan,
    required this.recipeName,
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

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('menu_day_$dayKey'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: plan.enabled
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : Colors.grey.withValues(alpha: 0.25),
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13,
                            color: plan.enabled
                                ? Colors.black54
                                : Colors.grey.shade400)),
                  ],
                ),
              ),
              Switch(
                key: Key('menu_day_switch_$dayKey'),
                value: plan.enabled,
                activeThumbColor: AppTheme.primary,
                onChanged: onToggle,
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editor del plan de un día (o de un override): lista de recetas con su
/// cantidad guía, agregar y quitar. Devuelve un _DayPlan al cerrar con guardar.
class _DayEditorSheet extends StatefulWidget {
  final String title;
  final _DayPlan plan;
  final List<Map<String, dynamic>> recipes;
  final String Function(String) recipeName;

  const _DayEditorSheet({
    required this.title,
    required this.plan,
    required this.recipes,
    required this.recipeName,
  });

  @override
  State<_DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<_DayEditorSheet> {
  late final List<_PlanItem> _items = widget.plan.items
      .map((it) => _PlanItem(it.recipeUuid, it.plannedQty))
      .toList();

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
      builder: (_) => _RecipePickerSheet(recipes: available),
    );
    if (picked != null) {
      setState(() => _items.add(_PlanItem(picked, 0)));
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
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Menú del ${widget.title.toLowerCase()}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  TextButton.icon(
                    key: const Key('menu_day_add_recipe'),
                    onPressed: widget.recipes.isEmpty ? null : _addRecipe,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar'),
                  ),
                ],
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
                        style: TextStyle(fontSize: 14.5, color: Colors.black54),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(widget.recipeName(it.recipeUuid),
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600)),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
        const Text('Preparar: ',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
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
  const _RecipePickerSheet({required this.recipes});

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
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No hay recetas para mostrar.',
                          style: TextStyle(color: Colors.black54)),
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
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600)),
                          subtitle: (r['category'] ?? '').toString().isEmpty
                              ? null
                              : Text(r['category'].toString()),
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
        const Divider(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text('Ajustes por fecha',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            TextButton.icon(
              key: const Key('menu_add_override'),
              onPressed: () => _addOverride(context),
              icon: const Icon(Icons.event_rounded),
              label: const Text('Ajustar fecha'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Cambie el menú de un día puntual (un festivo, un evento) sin tocar '
            'su plantilla semanal.',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.25),
          ),
        ),
        if (overrides.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Sin ajustes próximos.',
                style: TextStyle(color: Colors.black38)),
          )
        else
          for (final ov in overrides)
            Card(
              elevation: 0,
              color: Colors.grey.shade50,
              child: ListTile(
                key: Key('override_${ov['date']}'),
                leading: const Icon(Icons.event_available_rounded,
                    color: AppTheme.primary),
                title: Text(ov['date'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(ov['enabled'] == true
                    ? '${((ov['items'] as List?) ?? []).length} plato(s)'
                    : 'Cerrado ese día'),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Planeando la sede',
          prefixIcon: const Icon(Icons.store_mall_directory_rounded),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('menu_branch_selector'),
            isExpanded: true,
            value: selectedId,
            items: items,
            onChanged: (v) => onChanged(v ?? ''),
          ),
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
    return Card(
      elevation: 0,
      color: AppTheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.link_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Link de esta sede',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Text(url.replaceFirst('https://', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              key: const Key('menu_branch_link_copy'),
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copiar link',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                onSnack('Link de la sede copiado');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
