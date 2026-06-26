// Spec: specs/082-catalogo-online-personalizacion/spec.md
//
// Organizar catálogo (Fase 3): reordenar las categorías, ocultar productos del
// catálogo en línea y destacarlos. Cambia SOLO la tienda en línea (no el POS).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';

class _OrgProduct {
  final String id;
  final String name;
  final String category;
  bool hidden;
  bool featured;
  _OrgProduct(this.id, this.name, this.category, this.hidden, this.featured);
}

class CatalogOrganizeScreen extends StatefulWidget {
  final ApiService? api;
  const CatalogOrganizeScreen({super.key, this.api});

  @override
  State<CatalogOrganizeScreen> createState() => _CatalogOrganizeScreenState();
}

class _CatalogOrganizeScreenState extends State<CatalogOrganizeScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  final List<_OrgProduct> _products = [];
  List<String> _categoryOrder = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _noCat = 'Sin categoría';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.fetchProducts(perPage: 500),
        _api.fetchBusinessProfile(),
      ]);
      final prodRes = results[0];
      final profile = results[1];
      final list = (prodRes['data'] as List?) ?? const [];
      final saved = (((profile['data'] as Map?) ?? profile)['category_order']
              as List?)
          ?.map((e) => e.toString())
          .toList() ??
          <String>[];

      final products = <_OrgProduct>[];
      for (final raw in list) {
        final m = Map<String, dynamic>.from(raw as Map);
        final cat = ((m['category'] as String?)?.trim().isNotEmpty ?? false)
            ? (m['category'] as String).trim()
            : _noCat;
        products.add(_OrgProduct(
          m['id'] as String,
          (m['name'] as String?) ?? 'Producto',
          cat,
          (m['hidden_in_catalog'] as bool?) ?? false,
          (m['is_featured'] as bool?) ?? false,
        ));
      }

      // Orden de categorías: primero las guardadas (que aún existan), luego el
      // resto alfabético.
      final present = products.map((p) => p.category).toSet();
      final order = <String>[];
      for (final c in saved) {
        if (present.contains(c) && !order.contains(c)) order.add(c);
      }
      final rest = present.where((c) => !order.contains(c)).toList()..sort();
      order.addAll(rest);

      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(products);
        _categoryOrder = order;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar el catálogo.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.updateCatalogOrganization(
        categoryOrder: _categoryOrder.where((c) => c != _noCat).toList(),
        hiddenIds: _products.where((p) => p.hidden).map((p) => p.id).toList(),
        featuredIds: _products.where((p) => p.featured).map((p) => p.id).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Catálogo organizado ✓'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar: $e'), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Organizar catálogo', style: AppUI.title),
      ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppUI.s16),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(AppUI.s24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center, style: AppUI.bodySoft),
                    const SizedBox(height: AppUI.s8),
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                ))
              : _content(),
    );
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.all(AppUI.s16),
      children: [
        const Text('Arrastre para ordenar las categorías. Toque el ojo para '
            'ocultar un producto del catálogo y la estrella para destacarlo.',
            style: AppUI.bodySoft),
        const SizedBox(height: AppUI.s16),
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ORDEN DE CATEGORÍAS', style: AppUI.sectionLabel),
            const SizedBox(height: AppUI.s8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              onReorder: (oldI, newI) => setState(() {
                if (newI > oldI) newI -= 1;
                final item = _categoryOrder.removeAt(oldI);
                _categoryOrder.insert(newI, item);
              }),
              children: [
                for (final cat in _categoryOrder)
                  ListTile(
                    key: ValueKey('cat_$cat'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.drag_indicator_rounded, color: AppUI.inkSoft),
                    title: Text(cat, style: AppUI.bodyStrong),
                    trailing: Text(
                        '${_products.where((p) => p.category == cat).length}',
                        style: AppUI.bodySoft),
                  ),
              ],
            ),
          ]),
        ),
        const SizedBox(height: AppUI.s16),
        // Productos agrupados por la categoría en su orden actual.
        for (final cat in _categoryOrder) _categoryGroup(cat),
      ],
    );
  }

  Widget _categoryGroup(String cat) {
    final items = _products.where((p) => p.category == cat).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s12),
      child: SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cat.toUpperCase(), style: AppUI.sectionLabel),
          const SizedBox(height: 4),
          for (final p in items) _productRow(p),
        ]),
      ),
    );
  }

  Widget _productRow(_OrgProduct p) {
    return Row(children: [
      Expanded(
        child: Text(p.name,
            style: AppUI.bodyStrong.copyWith(
                fontSize: 15,
                color: p.hidden ? AppUI.inkSoft : AppTheme.textPrimary,
                decoration: p.hidden ? TextDecoration.lineThrough : null)),
      ),
      IconButton(
        tooltip: p.featured ? 'Quitar destacado' : 'Destacar',
        onPressed: () => setState(() => p.featured = !p.featured),
        icon: Icon(p.featured ? Icons.star_rounded : Icons.star_outline_rounded,
            color: p.featured ? const Color(0xFFF59E0B) : AppUI.inkSoft),
      ),
      IconButton(
        tooltip: p.hidden ? 'Mostrar en catálogo' : 'Ocultar del catálogo',
        onPressed: () => setState(() => p.hidden = !p.hidden),
        icon: Icon(
            p.hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: p.hidden ? AppTheme.error : AppUI.inkSoft),
      ),
    ]);
  }
}
