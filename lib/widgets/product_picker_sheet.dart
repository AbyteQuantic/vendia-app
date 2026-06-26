// Selector de producto reutilizable (bottom sheet con búsqueda). Devuelve el
// [Product] elegido o null. Extraído de quote_form para compartirlo entre
// cotizaciones, pedidos a proveedor (regularizar stock) y donde haga falta.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_cop.dart';

/// Abre el selector y devuelve el producto elegido (o null si se cierra).
Future<Product?> showProductPicker(BuildContext context, {ApiService? api}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProductPickerSheet(api: api),
  );
}

class ProductPickerSheet extends StatefulWidget {
  final ApiService? api;
  const ProductPickerSheet({super.key, this.api});

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  final _searchCtrl = TextEditingController();
  List<Product> _products = [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.fetchProducts(perPage: 200);
      final raw = (res['data'] as List?) ?? const [];
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los productos';
      });
    }
  }

  List<Product> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Elegir producto',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  key: const Key('product_picker_search'),
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'Buscar producto',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppTheme.primary, size: 24),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const Divider(height: 16),
              Flexible(child: _buildList(results)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<Product> results) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: AppTheme.warning),
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(fontSize: 17, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: _load,
              child: const Text('Reintentar', style: TextStyle(fontSize: 17))),
        ]),
      );
    }
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: Text('No hay productos.',
                style: TextStyle(fontSize: 17, color: AppTheme.textSecondary))),
      );
    }
    return ListView.separated(
      key: const Key('product_picker_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 12),
      itemBuilder: (_, i) {
        final p = results[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          title: Text(p.name,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          subtitle: Text(formatCOP(p.price),
              style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(p);
          },
        );
      },
    );
  }
}
