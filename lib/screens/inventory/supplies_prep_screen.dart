// Spec: specs/076-alistar-insumos-del-dia/spec.md
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import 'shopping_list_screen.dart';

/// Alistar insumos del día (Spec 076): toma el menú planeado para HOY o MAÑANA,
/// muestra cada plato con sus porciones esperadas (editables) y calcula EN VIVO
/// cuánto de cada insumo hay que alistar.
class SuppliesPrepScreen extends StatefulWidget {
  final ApiService? api;
  const SuppliesPrepScreen({super.key, this.api});

  @override
  State<SuppliesPrepScreen> createState() => _SuppliesPrepScreenState();
}

class _SuppliesPrepScreenState extends State<SuppliesPrepScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  int _dayOffset = 0; // 0 = hoy, 1 = mañana
  bool _loading = true;
  String? _error;
  String _weekday = '';
  List<Map<String, dynamic>> _dishes = [];
  final Map<String, int> _portions = {}; // recipe_uuid -> porciones (editable)

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateStr {
    final d = DateTime.now().add(Duration(days: _dayOffset));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchSuppliesPrepList(date: _dateStr);
      final dishes = (data['dishes'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _weekday = (data['weekday'] ?? '').toString();
        _dishes = dishes;
        _portions.clear();
        for (final d in dishes) {
          _portions[d['recipe_uuid'].toString()] =
              (d['default_portions'] as num?)?.toInt() ?? 10;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar el menú del día.';
        _loading = false;
      });
    }
  }

  /// Totales por insumo (recalculados en vivo): {key: {name, unit, qty}}.
  List<Map<String, dynamic>> get _totals {
    final acc = <String, Map<String, dynamic>>{};
    for (final dish in _dishes) {
      final p = _portions[dish['recipe_uuid'].toString()] ?? 0;
      for (final ing in (dish['ingredients'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(ing as Map);
        final id = (m['ingredient_id'] ?? m['name']).toString();
        final qpp = (m['qty_per_portion'] as num?)?.toDouble() ?? 0;
        acc.putIfAbsent(id, () => {
              'ingredient_id': m['ingredient_id'] ?? '',
              'name': m['name'],
              'unit': m['unit'],
              'qty': 0.0,
            });
        acc[id]!['qty'] = (acc[id]!['qty'] as double) + qpp * p;
      }
    }
    final list = acc.values.toList();
    list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Alistar del día', style: AppUI.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Toggle Hoy / Mañana.
            Padding(
              padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s8),
              child: Row(children: [
                _dayChip('Hoy', 0),
                const SizedBox(width: AppUI.s8),
                _dayChip('Mañana', 1),
                const Spacer(),
                if (_weekday.isNotEmpty)
                  Text(_weekday, style: AppUI.bodySoft),
              ]),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: (_loading || _error != null || _dishes.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s12),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    key: const Key('btn_buy_missing'),
                    onPressed: () {
                      final needs = _totals
                          .map((t) => {
                                'ingredient_id': t['ingredient_id'],
                                'name': t['name'],
                                'unit': t['unit'],
                                'qty': t['qty'],
                              })
                          .toList();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ShoppingListScreen(needs: needs)));
                    },
                    icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                    label: const Text('Comprar lo que falta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _dayChip(String label, int offset) {
    final sel = _dayOffset == offset;
    return ChoiceChip(
      key: Key('day_$offset'),
      label: Text(label),
      selected: sel,
      onSelected: (_) {
        setState(() => _dayOffset = offset);
        _load();
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppUI.radiusSm),
        side: BorderSide(color: sel ? AppTheme.primary : AppUI.border),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: AppUI.bodySoft),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }
    if (_dishes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppUI.s24),
          child: Text('No hay menú planeado para este día.\nPrograme el menú en "Planear menú".',
              textAlign: TextAlign.center, style: AppUI.bodySoft),
        ),
      );
    }
    final totals = _totals;
    return ListView(
      key: const Key('prep_list'),
      padding: const EdgeInsets.fromLTRB(AppUI.s16, 0, AppUI.s16, AppUI.s24),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('PLATOS DEL MENÚ', style: AppUI.sectionLabel),
        ),
        for (final d in _dishes) _dishRow(d),
        const SizedBox(height: AppUI.s16),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('NECESITA ALISTAR', style: AppUI.sectionLabel),
        ),
        Container(
          decoration: AppUI.card(r: 10),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (int i = 0; i < totals.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppUI.hairline),
                _totalRow(totals[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _dishRow(Map<String, dynamic> d) {
    final id = d['recipe_uuid'].toString();
    final p = _portions[id] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Row(
        children: [
          Expanded(child: Text(d['name'].toString(), style: AppUI.bodyStrong)),
          IconButton(
            key: Key('p_minus_$id'),
            iconSize: 22,
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppUI.inkSoft),
            onPressed: p <= 0 ? null : () => setState(() => _portions[id] = p - 1),
          ),
          SizedBox(
            width: 36,
            child: Text('$p',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          IconButton(
            key: Key('p_plus_$id'),
            iconSize: 22,
            icon: const Icon(Icons.add_circle_rounded, color: AppTheme.primary),
            onPressed: () => setState(() => _portions[id] = p + 1),
          ),
          const Text('porc.', style: AppUI.bodySoft),
        ],
      ),
    );
  }

  Widget _totalRow(Map<String, dynamic> t) {
    final qty = (t['qty'] as double);
    final pretty = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: 12),
      child: Row(children: [
        Expanded(child: Text(t['name'].toString(), style: AppUI.bodyStrong)),
        Text('$pretty ${t['unit']}',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: AppTheme.primary,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }
}
