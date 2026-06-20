// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';

/// Catálogo de un proveedor + armar pedido (Spec 075 F3). La tienda escoge
/// cantidades, la entrega, y cierra por WhatsApp. VendIA solo conecta.
class SupplierCatalogScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;
  final ApiService? api;
  const SupplierCatalogScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
    this.api,
  });

  @override
  State<SupplierCatalogScreen> createState() => _SupplierCatalogScreenState();
}

class _SupplierCatalogScreenState extends State<SupplierCatalogScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = [];
  final Map<String, double> _cart = {}; // productId -> qty
  String _delivery = 'por_acordar';
  bool _sending = false;

  static const _deliveryOptions = {
    'proveedor_entrega': 'El proveedor lleva',
    'tienda_recoge': 'Yo recojo',
    'por_acordar': 'Lo acordamos',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchSupplierCatalog(widget.supplierId);
      final prods = (data['products'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _products = prods;
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

  double get _total {
    double t = 0;
    for (final p in _products) {
      final q = _cart[p['id']] ?? 0;
      t += q * ((p['price'] as num?)?.toDouble() ?? 0);
    }
    return t;
  }

  int get _itemCount => _cart.values.where((q) => q > 0).length;

  Future<void> _order() async {
    final items = _products
        .where((p) => (_cart[p['id']] ?? 0) > 0)
        .map((p) => {
              'product_id': p['id'],
              'name': p['name'],
              'quantity': _cart[p['id']],
              'price': p['price'],
            })
        .toList();
    if (items.isEmpty) return;
    setState(() => _sending = true);
    try {
      final res = await _api.placeSupplierOrder(
          widget.supplierId, items, _delivery);
      final url = (res['whatsapp_url'] ?? '').toString();
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido enviado. Ciérrelo por WhatsApp.'),
          backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppError ? e.message : 'No se pudo enviar el pedido.'),
          backgroundColor: AppTheme.error));
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
        title: Text(widget.supplierName.replaceFirst('[SEED] ', ''),
            style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : ListView.separated(
                  key: const Key('supplier_catalog_list'),
                  padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, 160),
                  itemCount: _products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
                  itemBuilder: (_, i) => _productRow(_products[i]),
                ),
      bottomNavigationBar: _loading || _error != null ? null : _bottomBar(),
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final id = p['id'].toString();
    final qty = _cart[id] ?? 0;
    final expiry = (p['expiry_date'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'].toString(), style: AppUI.bodyStrong),
                const SizedBox(height: 2),
                Row(children: [
                  Text('\$${((p['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  if (expiry.isNotEmpty) ...[
                    const SizedBox(width: AppUI.s8),
                    MinimalBadge(label: 'vence $expiry', color: AppTheme.warning),
                  ],
                ]),
              ],
            ),
          ),
          _stepper(id, qty),
        ],
      ),
    );
  }

  Widget _stepper(String id, double qty) {
    return Row(
      children: [
        IconButton(
          key: Key('minus_$id'),
          iconSize: 22,
          icon: const Icon(Icons.remove_circle_outline_rounded, color: AppUI.inkSoft),
          onPressed: qty <= 0 ? null : () => setState(() {
            final n = qty - 1;
            if (n <= 0) {
              _cart.remove(id);
            } else {
              _cart[id] = n;
            }
          }),
        ),
        SizedBox(
          width: 24,
          child: Text('${qty.toInt()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
        IconButton(
          key: Key('plus_$id'),
          iconSize: 22,
          icon: const Icon(Icons.add_circle_rounded, color: AppTheme.primary),
          onPressed: () => setState(() => _cart[id] = qty + 1),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppUI.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Cómo recibe el pedido?', style: AppUI.sectionLabel),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final e in _deliveryOptions.entries)
                  ChoiceChip(
                    key: Key('delivery_${e.key}'),
                    label: Text(e.value, style: const TextStyle(fontSize: 13)),
                    selected: _delivery == e.key,
                    onSelected: (_) => setState(() => _delivery = e.key),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUI.radiusSm),
                      side: BorderSide(
                          color: _delivery == e.key ? AppTheme.primary : AppUI.border),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppUI.s8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _itemCount == 0
                        ? 'Agregue productos'
                        : '$_itemCount ítem(s) · \$${_total.toStringAsFixed(0)}',
                    style: AppUI.bodyStrong,
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    key: const Key('btn_order_whatsapp'),
                    onPressed: _itemCount == 0 || _sending ? null : _order,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('Pedir por WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
