// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../widgets/branch_selector_drawer.dart';

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

  // PERF: total/conteo cacheados (antes recorrían todo el catálogo en cada
  // build/tap). Se recalculan solo al tocar un stepper.
  double _total = 0;
  int _itemCount = 0;

  void _recalcCart() {
    double t = 0;
    int n = 0;
    for (final p in _products) {
      final q = _cart[p['id']] ?? 0;
      if (q > 0) {
        n++;
        t += q * ((p['price'] as num?)?.toDouble() ?? 0);
      }
    }
    _total = t;
    _itemCount = n;
  }

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.supplierName.replaceFirst('[SEED] ', ''),
                style: AppUI.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Text('Catálogo · proveedor en VendIA',
                style: TextStyle(fontSize: 12, color: AppUI.inkSoft)),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
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

  // Tarjeta de producto estilo Soft-UI / Bento (skill ui-ux-pro-max):
  // thumbnail, esquinas suaves (18), sombra sutil, realce al seleccionar.
  Widget _productRow(Map<String, dynamic> p) {
    final id = p['id'].toString();
    final qty = _cart[id] ?? 0;
    final selected = qty > 0;
    final expiry = _fmtDate((p['expiry_date'] ?? '').toString());
    final photo = (p['photo_url'] ?? '').toString();
    final category = (p['category'] ?? '').toString();
    final price = (p['price'] as num?)?.toDouble() ?? 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppUI.shadow,
        border: selected
            ? Border.all(color: AppTheme.primary, width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Row(
        children: [
          // Thumbnail (o ícono de respaldo).
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 60,
              height: 60,
              color: AppUI.pageBg,
              child: photo.isNotEmpty
                  ? Image.network(photo, fit: BoxFit.cover,
                      // PERF: decodifica a ~3× el tamaño mostrado (60dp), no a
                      // resolución completa → menos memoria/jank en la lista.
                      cacheWidth: 180, cacheHeight: 180,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.inventory_2_outlined, color: AppUI.inkSoft))
                  : const Icon(Icons.inventory_2_outlined, color: AppUI.inkSoft),
            ),
          ),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.bodyStrong.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('\$${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  if (category.isNotEmpty) ...[
                    const SizedBox(width: AppUI.s8),
                    Flexible(
                      child: Text(category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppUI.bodySoft.copyWith(fontSize: 12)),
                    ),
                  ],
                ]),
                if (expiry.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MinimalBadge(label: 'vence $expiry', color: AppTheme.warning),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppUI.s8),
          _stepper(id, qty),
        ],
      ),
    );
  }

  // Stepper en "pill" suave (− qty +). Más moderno que IconButtons sueltos.
  Widget _stepper(String id, double qty) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _qtyBtn(
          key: Key('minus_$id'),
          icon: Icons.remove_rounded,
          color: qty <= 0 ? AppUI.inkSoft : AppTheme.primary,
          onTap: qty <= 0
              ? null
              : () => setState(() {
                    final n = qty - 1;
                    if (n <= 0) {
                      _cart.remove(id);
                    } else {
                      _cart[id] = n;
                    }
                    _recalcCart();
                  }),
        ),
        SizedBox(
          width: 26,
          child: Text('${qty.toInt()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
        _qtyBtn(
          key: Key('plus_$id'),
          icon: Icons.add_rounded,
          color: AppTheme.primary,
          onTap: () => setState(() {
            _cart[id] = qty + 1;
            _recalcCart();
          }),
        ),
      ]),
    );
  }

  Widget _qtyBtn({
    required Key key,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkResponse(
      key: key,
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  // ISO ("2026-07-10T00:00:00Z") → "10/07/2026". Si no parsea, toma la fecha
  // (parte antes de la T); vacío si no hay.
  String _fmtDate(String raw) {
    if (raw.trim().isEmpty) return '';
    final d = DateTime.tryParse(raw);
    if (d != null) {
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      return '$dd/$mm/${d.year}';
    }
    return raw.split('T').first;
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s12),
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
            // Resumen arriba + botón de ancho completo abajo: evita que el botón
            // largo ahogue el texto (antes el Expanded quedaba sin ancho y el
            // texto se partía letra por letra).
            Text(
              _itemCount == 0
                  ? 'Agregue productos para pedir'
                  : '$_itemCount ítem(s) · \$${_total.toStringAsFixed(0)}',
              style: AppUI.bodyStrong,
            ),
            const SizedBox(height: AppUI.s8),
            SizedBox(
              width: double.infinity,
              height: 50,
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
        ),
      ),
    );
  }
}
