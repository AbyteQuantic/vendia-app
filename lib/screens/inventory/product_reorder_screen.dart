// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/format_cop.dart';
import '../mandados/mandados_screen.dart';

/// 🏪 Productos de tienda por reordenar (en/bajo su mínimo). Distinto de los
/// INSUMOS del menú: aquí se compra el PRODUCTO mismo. "Crear mandado" arma una
/// lista de compra de productos que luego se ingresa con "Ya compré" (entra al
/// stock del producto). Spec 078 B2 — cierra el carril de reorden de tienda.
class ProductReorderScreen extends StatefulWidget {
  const ProductReorderScreen({super.key, this.api});
  final ApiService? api;

  @override
  State<ProductReorderScreen> createState() => _ProductReorderScreenState();
}

class _ProductReorderScreenState extends State<ProductReorderScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  List<Map<String, dynamic>> _items = [];
  double _total = 0;
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.fetchProductReorderList();
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _total = res.total;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos cargar los productos por reordenar.';
      });
    }
  }

  Future<void> _createErrand() async {
    setState(() => _creating = true);
    try {
      final lines = _items.map((m) {
        final shortfall = (m['shortfall'] as num?)?.toDouble() ?? 0;
        final price = (m['unit_price'] as num?)?.toDouble() ?? 0;
        return {
          'product_id': (m['product_uuid'] ?? '').toString(),
          'line_kind': 'product',
          'name': (m['name'] ?? '').toString(),
          'unit': (m['unit'] ?? 'unidad').toString(),
          'qty': shortfall,
          'unit_price': price,
          'cost': shortfall * price,
          'is_estimate': price <= 0,
        };
      }).toList();
      await _api.createErrand(lines: lines, assigneeType: 'self', title: 'Reposición de productos');
      if (!mounted) return;
      final nav = Navigator.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Mandado creado. Cuando compre, márquelo en Pendientes para ingresarlo al inventario.'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ver pendientes',
          textColor: Colors.white,
          onPressed: () => nav.push(MaterialPageRoute(builder: (_) => const MandadosScreen())),
        ),
      ));
      nav.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo crear el mandado.'), backgroundColor: AppTheme.error));
      }
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
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Productos por reordenar', style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppUI.s24),
                        child: Text('Todo en orden 🏪\nNingún producto de tienda está bajo su mínimo.',
                            textAlign: TextAlign.center, style: AppUI.bodySoft),
                      ),
                    )
                  : Column(children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, 0),
                        child: Row(children: [
                          Text('🏪 ', style: TextStyle(fontSize: 16)),
                          Expanded(child: Text('Productos de tienda — se compra el producto mismo.', style: AppUI.bodySoft)),
                        ]),
                      ),
                      Expanded(
                        child: ListView.separated(
                          key: const Key('reorder_list'),
                          padding: const EdgeInsets.all(AppUI.s16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
                          itemBuilder: (_, i) => _row(_items[i]),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(AppUI.s16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const Key('create_reorder_errand'),
                              onPressed: _creating ? null : _createErrand,
                              icon: _creating
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                                  : const Icon(Icons.add_shopping_cart_rounded, size: 18),
                              label: Text(_total > 0 ? 'Crear mandado · ≈ ${formatCOP(_total)}' : 'Crear mandado de compra'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                          ),
                        ),
                      ),
                    ]),
    );
  }

  Widget _row(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString();
    final shortfall = (m['shortfall'] as num?)?.toInt() ?? 0;
    final cost = (m['estimated_cost'] as num?)?.toDouble() ?? 0;
    final isEstimate = m['is_estimate'] == true;
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AppUI.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('Faltan $shortfall · stock ${m['stock']} de mín. ${m['min_stock']}', style: AppUI.bodySoft.copyWith(fontSize: 12)),
          ]),
        ),
        const SizedBox(width: AppUI.s8),
        Text(cost > 0 ? '${isEstimate ? "≈ " : ""}${formatCOP(cost)}' : 'sin precio',
            style: AppUI.bodyStrong.copyWith(color: AppTheme.primary)),
      ]),
    );
  }
}
