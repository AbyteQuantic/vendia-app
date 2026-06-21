// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../utils/format_cop.dart';
import '../suppliers/nearby_suppliers_screen.dart';

/// Etiqueta + color del ORIGEN de un precio (Spec 077): el tenant ve de qué
/// mercado viene cada precio y si es estimado.
({String label, Color color}) _sourceBadge(String source) {
  switch (source) {
    case 'vendia_catalog':
      return (label: 'VendIA', color: AppTheme.primary);
    case 'manual':
      return (label: 'Mi precio', color: AppTheme.success);
    case 'invoice_ocr':
      return (label: 'Factura', color: AppUI.inkSoft);
    case 'scraped_chain':
      return (label: 'Cadena', color: AppTheme.warning);
    case 'ultima_compra':
      return (label: 'Últ. compra', color: AppTheme.warning);
    default:
      return (label: 'Sin precio', color: AppUI.inkSoft);
  }
}

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
    final b = StringBuffer('Buenos días, necesito comprar:\n');
    for (final it in _items) {
      final n = (it['shortfall'] as num?)?.toDouble() ?? 0;
      b.writeln('• ${it['name']} — ${_fmt(n)} ${it['unit']}');
    }
    b.writeln('\nTotal aprox: ${formatCOP(_total)}');
    return b.toString();
  }

  /// Abre WhatsApp con la lista ya escrita para elegir el contacto a quién
  /// enviarla (proveedor, empleado, etc.). Sin número → WhatsApp deja elegir.
  Future<void> _sendByWhatsApp() async {
    final url = 'https://wa.me/?text=${Uri.encodeComponent(_buildMessage())}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
    final src = _sourceBadge((it['price_source'] ?? '').toString());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodyStrong)),
            const SizedBox(width: AppUI.s8),
            // Costo con moneda COP + origen del precio (de qué mercado viene).
            Text(formatCOP(cost),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('Faltan ${_fmt(shortfall)} ${it['unit']}', style: AppUI.bodySoft),
            const SizedBox(width: AppUI.s8),
            MinimalBadge(label: src.label, color: src.color),
            const Spacer(),
            // Una sola acción clara para explorar mercados/precios por producto.
            InkWell(
              key: Key('options_${it['ingredient_id']}'),
              onTap: () => _showChainPrices(it),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Text('Ver opciones',
                    style: TextStyle(fontSize: 12, color: AppTheme.primary, decoration: TextDecoration.underline)),
              ),
            ),
          ]),
        ],
      ),
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
              Text('${it['name']} · opciones de precio', style: AppUI.bodyStrong),
              const SizedBox(height: AppUI.s4),
              const Text('Precios en cadenas (referencia)', style: AppUI.sectionLabel),
              const SizedBox(height: 4),
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
                      Text(formatCOP((c['price'] as num?)?.toDouble() ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                  );
                }),
              const SizedBox(height: AppUI.s8),
              const Text('Precios de referencia de catálogos en línea; pueden variar.',
                  style: TextStyle(fontSize: 11, color: AppUI.inkSoft)),
              const SizedBox(height: AppUI.s12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: Key('register_price_${it['ingredient_id']}'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editPrice(it);
                  },
                  icon: const Icon(Icons.sell_rounded, size: 18),
                  label: const Text('Registrar mi precio de proveedor'),
                ),
              ),
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
            Text(formatCOP(_total),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: AppUI.s8),
          // Acción primaria única (sin sobreposición): enviar la lista por
          // WhatsApp (abre WhatsApp con el mensaje listo para elegir contacto).
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('btn_send_list'),
              onPressed: _sendByWhatsApp,
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Enviar por WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              key: const Key('btn_nearby_from_shopping'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NearbySuppliersScreen())),
              icon: const Icon(Icons.storefront_rounded, size: 18, color: AppTheme.primary),
              label: const Text('Ver proveedores cerca', style: TextStyle(color: AppTheme.primary)),
            ),
          ),
        ]),
      ),
    );
  }
}
