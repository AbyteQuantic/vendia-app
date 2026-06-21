// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../suppliers/nearby_suppliers_screen.dart';

/// Comprar lo que falta (Spec 077 F1): de los insumos del menú menos el stock,
/// muestra el faltante + precio sugerido (con su origen) + costo estimado, y
/// lleva a comprar con proveedores cercanos o a compartir la lista.
class ShoppingListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> needs; // [{ingredient_id, name, unit, qty}]
  final ApiService? api;
  const ShoppingListScreen({super.key, required this.needs, this.api});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  double _total = 0;
  bool _hasEstimate = false;
  String _disclaimer = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchShoppingList(widget.needs);
      final items = (data['items'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = (data['total_estimated'] as num?)?.toDouble() ?? 0;
        _hasEstimate = data['has_estimate'] == true;
        _disclaimer = (data['disclaimer'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos calcular la compra.';
        _loading = false;
      });
    }
  }

  String _buildMessage() {
    final b = StringBuffer('Necesito comprar:\n');
    for (final it in _items) {
      final n = (it['shortfall'] as num?)?.toDouble() ?? 0;
      b.writeln('• ${it['name']} — ${_fmt(n)} ${it['unit']}');
    }
    return b.toString();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

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
        title: const Text('Comprar lo que falta', style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppUI.s24),
                      child: Text('¡Tiene todo! No le falta ningún insumo para el menú.',
                          textAlign: TextAlign.center, style: AppUI.bodySoft),
                    ))
                  : _body(),
      bottomNavigationBar: _items.isEmpty || _loading ? null : _bottomBar(),
    );
  }

  Widget _body() {
    return ListView(
      key: const Key('shopping_list'),
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, 150),
      children: [
        Container(
          decoration: AppUI.card(r: 10),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (int i = 0; i < _items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppUI.hairline),
              _itemRow(_items[i]),
            ],
          ]),
        ),
        if (_hasEstimate) ...[
          const SizedBox(height: AppUI.s12),
          Container(
            padding: const EdgeInsets.all(AppUI.s12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppUI.radiusSm),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 18),
              const SizedBox(width: AppUI.s8),
              Expanded(child: Text(_disclaimer, style: const TextStyle(fontSize: 12, color: AppUI.ink, height: 1.3))),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _itemRow(Map<String, dynamic> it) {
    final shortfall = (it['shortfall'] as num?)?.toDouble() ?? 0;
    final cost = (it['estimated_cost'] as num?)?.toDouble() ?? 0;
    final estimate = it['is_estimate'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: 11),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it['name'].toString(), style: AppUI.bodyStrong),
            const SizedBox(height: 2),
            Row(children: [
              Text('Faltan ${_fmt(shortfall)} ${it['unit']}', style: AppUI.bodySoft),
              if (estimate) ...[
                const SizedBox(width: AppUI.s8),
                const MinimalBadge(label: 'Estimado', color: AppTheme.warning),
              ],
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${cost.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                  fontFeatures: [FontFeature.tabularFigures()])),
          Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              key: Key('chains_${it['ingredient_id']}'),
              onTap: () => _showChainPrices(it),
              child: const Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Text('En cadenas',
                    style: TextStyle(fontSize: 11, color: AppUI.inkSoft, decoration: TextDecoration.underline)),
              ),
            ),
            InkWell(
              key: Key('set_price_${it['ingredient_id']}'),
              onTap: () => _editPrice(it),
              child: const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Tengo mejor precio',
                    style: TextStyle(fontSize: 11, color: AppTheme.primary, decoration: TextDecoration.underline)),
              ),
            ),
          ]),
        ]),
      ]),
    );
  }

  Future<void> _showChainPrices(Map<String, dynamic> it) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _api.fetchChainPrices(it['name'].toString()),
        builder: (ctx, snap) {
          const pad = EdgeInsets.all(AppUI.s16);
          if (!snap.hasData) {
            return const Padding(
                padding: EdgeInsets.all(AppUI.s24),
                child: Center(child: CircularProgressIndicator()));
          }
          final m = snap.data!;
          return Padding(
            padding: pad,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${it['name']} · en cadenas', style: AppUI.bodyStrong),
              const SizedBox(height: AppUI.s8),
              if (m.isEmpty)
                const Text('Aún no tenemos precios de cadenas para este insumo.', style: AppUI.bodySoft)
              else
                ...m.map((c) {
                  final dropped = c['dropped'] == true;
                  final pct = (c['drop_pct'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text((c['chain'] ?? '').toString().toUpperCase(), style: AppUI.bodyStrong)),
                      if (dropped) ...[
                        MinimalBadge(label: 'bajó ${pct.toStringAsFixed(0)}%', color: AppTheme.success),
                        const SizedBox(width: AppUI.s8),
                      ],
                      Text('\$${((c['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                  );
                }),
              const SizedBox(height: AppUI.s8),
              const Text('Precios de referencia de catálogos en línea; pueden variar.',
                  style: TextStyle(fontSize: 11, color: AppUI.inkSoft)),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _editPrice(Map<String, dynamic> it) async {
    final ctrl = TextEditingController();
    final supplierCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Precio de ${it['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('price_input'),
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Precio por ${it['unit']} (\$)'),
          ),
          TextField(
            controller: supplierCtrl,
            decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            key: const Key('price_save'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final price = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    if (price <= 0) return;
    try {
      await _api.addSupplyPrice(
        ingredientId: it['ingredient_id'].toString(),
        rawName: it['name'].toString(),
        unitPrice: price,
        supplierName: supplierCtrl.text.trim(),
      );
      await _load(); // recalcula con el nuevo precio (ya no estimado)
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo guardar el precio.'), backgroundColor: AppTheme.error));
      }
    }
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppUI.border)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Total estimado', style: AppUI.bodyStrong)),
            Text('\$${_total.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: AppUI.s8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('btn_share_list'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _buildMessage()));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Lista copiada. Péguela en WhatsApp.'),
                      backgroundColor: AppTheme.success));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar lista'),
              ),
            ),
            const SizedBox(width: AppUI.s8),
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('btn_nearby_from_shopping'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NearbySuppliersScreen())),
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text('Proveedores cerca'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
