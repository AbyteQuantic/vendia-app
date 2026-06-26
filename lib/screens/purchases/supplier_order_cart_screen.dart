// Spec: specs/082-catalogo-online-personalizacion/spec.md (pedido a proveedor
// desde Regularizar stock).
//
// Carrito de pedido a proveedor MULTI-PROVEEDOR: el tendero arma la lista,
// asigna un proveedor a TODO el pedido o a productos individuales, y cada
// proveedor se muestra como su propio sub-carrito que se envía por separado
// (WhatsApp del proveedor vía createErrand). Puede ver el catálogo del
// proveedor para pedir desde ahí.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/product_picker_sheet.dart';
import '../../widgets/supplier_picker_sheet.dart';
import '../suppliers/supplier_catalog_screen.dart';
import '../suppliers/nearby_suppliers_screen.dart';

class SupplierOrderCartScreen extends StatefulWidget {
  /// Líneas iniciales: mapas {uuid?, name, qty}.
  final List<Map<String, dynamic>> initialLines;
  final ApiService? api;

  const SupplierOrderCartScreen({
    super.key,
    required this.initialLines,
    this.api,
  });

  @override
  State<SupplierOrderCartScreen> createState() => _SupplierOrderCartScreenState();
}

class _SupplierOrderCartScreenState extends State<SupplierOrderCartScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  // Cada línea: {uuid?, name, qty, supplierId?, supplierName?, supplierPhone?}
  late final List<Map<String, dynamic>> _lines = widget.initialLines
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  bool _sending = false;

  int _qty(Map<String, dynamic> l) => (l['qty'] as num?)?.toInt() ?? 1;
  String _sid(Map<String, dynamic> l) => (l['supplierId'] ?? '').toString();

  // Agrupa por proveedor preservando el orden; '' = sin proveedor.
  Map<String, List<Map<String, dynamic>>> get _groups {
    final m = <String, List<Map<String, dynamic>>>{};
    for (final l in _lines) {
      (m[_sid(l)] ??= []).add(l);
    }
    return m;
  }

  void _setQty(Map<String, dynamic> l, int q) {
    if (q < 1) return;
    setState(() => l['qty'] = q);
  }

  void _remove(Map<String, dynamic> l) => setState(() => _lines.remove(l));

  Future<void> _addProduct() async {
    final prod = await showProductPicker(context, api: _api);
    if (prod == null || !mounted) return;
    if (_lines.any((l) => l['uuid'] == prod.uuid)) {
      _snack('${prod.name} ya está en el pedido.');
      return;
    }
    setState(() => _lines.add({'uuid': prod.uuid, 'name': prod.name, 'qty': 1}));
  }

  // Asigna un proveedor a las líneas dadas (o a todas si lines == null).
  Future<void> _assign(List<Map<String, dynamic>>? lines) async {
    final s = await showSupplierPicker(context, api: _api);
    if (s == null || !mounted) return;
    setState(() {
      for (final l in (lines ?? _lines)) {
        l['supplierId'] = s['id'];
        l['supplierName'] = s['company_name'];
        l['supplierPhone'] = s['phone'] ?? '';
      }
    });
  }

  // Directorio de proveedores suscritos a VendIA (cercanos) + sus catálogos.
  Future<void> _openVendiaSuppliers() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const NearbySuppliersScreen(),
    ));
  }

  Future<void> _openCatalog(String supplierId, String supplierName) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SupplierCatalogScreen(
        supplierId: supplierId,
        supplierName: supplierName,
      ),
    ));
  }

  Future<void> _sendGroup(List<Map<String, dynamic>> group) async {
    if (group.isEmpty || _sending) return;
    final first = group.first;
    setState(() => _sending = true);
    try {
      final dispatchLines = group
          .map((l) => <String, dynamic>{
                'name': l['name'],
                'unit': 'und',
                'shortfall': _qty(l),
                'price_per_unit': 0,
                'estimated_cost': 0,
                'ingredient_id': null,
                'price_source': 'manual',
                'is_estimate': true,
              })
          .toList();
      final res = await _api.createErrand(
        lines: dispatchLines,
        assigneeType: 'supplier',
        assigneeId: _sid(first),
        assigneeName: (first['supplierName'] ?? '').toString(),
        assigneePhone: (first['supplierPhone'] ?? '').toString(),
        title: 'Pedido a proveedor',
      );
      final url = (res['whatsapp_url'] ?? '').toString();
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      setState(() => _lines.removeWhere((l) => group.contains(l)));
      _snack(url.isNotEmpty ? 'Pedido enviado a ${first['supplierName']}.' : 'Pedido guardado en pendientes.');
      if (_lines.isEmpty) Navigator.of(context).pop(_lines);
    } catch (e) {
      _snack('No se pudo enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontSize: 15)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.success));
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final keys = groups.keys.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : 0)); // sin-proveedor al final
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_lines);
      },
      child: Scaffold(
        backgroundColor: AppUI.pageBg,
        appBar: AppBar(
          backgroundColor: AppUI.pageBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink),
            onPressed: () => Navigator.of(context).pop(_lines),
          ),
          title: const Text('Pedido al proveedor', style: AppUI.title),
          actions: [
            if (_lines.isNotEmpty)
              TextButton(
                onPressed: () => _assign(null),
                child: const Text('Asignar a todo',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        body: _lines.isEmpty
            ? _empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
                children: [
                  if (groups.containsKey('') && groups.length > 1)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppUI.s8),
                      child: Text('Asigne un proveedor a cada producto para enviar su pedido.',
                          style: AppUI.bodySoft),
                    ),
                  for (final k in keys) _group(k, groups[k]!),
                  const SizedBox(height: AppUI.s12),
                  OutlinedButton.icon(
                    onPressed: _addProduct,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppUI.border),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Agregar producto'),
                  ),
                  const SizedBox(height: AppUI.s8),
                  // Acceso al directorio B2B: proveedores suscritos a VendIA
                  // (cercanos) con su catálogo para pedir directo.
                  OutlinedButton.icon(
                    onPressed: _openVendiaSuppliers,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppUI.border),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                    ),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: const Text('Buscar proveedores en VendIA'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _group(String supplierId, List<Map<String, dynamic>> lines) {
    final assigned = supplierId.isNotEmpty;
    final name = assigned ? (lines.first['supplierName'] ?? 'Proveedor').toString() : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s12),
      child: SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cabecera del sub-carrito.
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (assigned ? AppTheme.primary : AppTheme.warning)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                  assigned ? Icons.local_shipping_rounded : Icons.help_outline_rounded,
                  size: 20,
                  color: assigned ? AppTheme.primary : AppTheme.warning),
            ),
            const SizedBox(width: AppUI.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(assigned ? name : 'Sin proveedor asignado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.bodyStrong.copyWith(
                        color: assigned ? AppTheme.textPrimary : AppTheme.warning)),
                Text('${lines.length} producto${lines.length == 1 ? "" : "s"}',
                    style: AppUI.bodySoft.copyWith(fontSize: 12)),
              ]),
            ),
            if (assigned)
              TextButton(
                onPressed: () => _openCatalog(supplierId, name),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Ver catálogo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
          ]),
          const Divider(height: AppUI.s16),
          for (final l in lines) _lineRow(l, assigned),
          const SizedBox(height: AppUI.s8),
          if (assigned)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : () => _sendGroup(lines),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text('Enviar a $name (${lines.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => _assign(lines),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                ),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Asignar proveedor',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _lineRow(Map<String, dynamic> l, bool assigned) {
    final q = _qty(l);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((l['name'] ?? 'Producto').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppUI.bodyStrong.copyWith(fontSize: 15)),
            // Por-producto: cambiar/asignar su proveedor (independiente del grupo).
            InkWell(
              onTap: () => _assign([l]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(assigned ? 'Cambiar proveedor' : 'Asignar proveedor a este',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: AppUI.s8),
        // Stepper en pill suave (consistente con el catálogo).
        Container(
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _StepperButton(icon: Icons.remove_rounded, onTap: () => _setQty(l, q - 1)),
            SizedBox(
              width: 26,
              child: Text('$q',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            _StepperButton(icon: Icons.add_rounded, onTap: () => _setQty(l, q + 1)),
          ]),
        ),
        IconButton(
          tooltip: 'Quitar',
          onPressed: () => _remove(l),
          icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
        ),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppUI.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_cart_outlined, size: 52, color: AppUI.inkSoft),
            const SizedBox(height: AppUI.s12),
            const Text('Su pedido está vacío', style: AppUI.bodyStrong),
            const SizedBox(height: 6),
            const Text('Agregue productos para enviarle la lista a su proveedor.',
                textAlign: TextAlign.center, style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s16),
            OutlinedButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar producto'),
            ),
            const SizedBox(height: AppUI.s8),
            TextButton.icon(
              onPressed: _openVendiaSuppliers,
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: const Text('Buscar proveedores en VendIA'),
            ),
          ]),
        ),
      );
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20, color: AppTheme.primary),
      ),
    );
  }
}
