// Spec: specs/082-catalogo-online-personalizacion/spec.md (deriva del pedido a
// proveedor desde Regularizar stock).
//
// Carrito interno del pedido al proveedor: el tendero revisa las líneas que va
// armando, ajusta cantidades, quita o agrega productos, y recién ahí lo envía
// (proveedor / empleado / WhatsApp vía showDispatchSheet). Devuelve, al volver,
// la lista actual de líneas (vacía si ya se envió).
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/dispatch_sheet.dart';
import '../../widgets/product_picker_sheet.dart';

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
  late final List<Map<String, dynamic>> _lines = widget.initialLines
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  bool _sending = false;

  int _qty(Map<String, dynamic> l) => (l['qty'] as num?)?.toInt() ?? 1;

  void _setQty(int i, int q) {
    if (q < 1) return;
    setState(() => _lines[i] = {..._lines[i], 'qty': q});
  }

  void _remove(int i) => setState(() => _lines.removeAt(i));

  Future<void> _addProduct() async {
    final prod = await showProductPicker(context, api: _api);
    if (prod == null || !mounted) return;
    if (_lines.any((l) => l['uuid'] == prod.uuid)) {
      _snack('${prod.name} ya está en el pedido.');
      return;
    }
    setState(() => _lines.add({'uuid': prod.uuid, 'name': prod.name, 'qty': 1}));
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontSize: 15)),
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _send() async {
    if (_lines.isEmpty || _sending) return;
    setState(() => _sending = true);
    final dispatchLines = _lines
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
    final sent = await showDispatchSheet(context, dispatchLines, 0, api: _api);
    if (!mounted) return;
    if (sent == true) {
      _lines.clear();
      Navigator.of(context).pop(_lines); // vacío → quien abrió limpia su selección
      return;
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
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
        ),
        body: _lines.isEmpty
            ? _empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
                children: [
                  Text('${_lines.length} producto${_lines.length == 1 ? "" : "s"} en el pedido',
                      style: AppUI.sectionLabel),
                  const SizedBox(height: AppUI.s8),
                  for (var i = 0; i < _lines.length; i++) _lineCard(i),
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
                ],
              ),
        bottomNavigationBar: _lines.isEmpty ? null : _sendBar(),
      ),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    final q = _qty(l);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s8),
      child: SoftCard(
        child: Row(children: [
          Expanded(
            child: Text((l['name'] ?? 'Producto').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppUI.bodyStrong.copyWith(fontSize: 15)),
          ),
          const SizedBox(width: AppUI.s8),
          _StepperButton(icon: Icons.remove_rounded, onTap: () => _setQty(i, q - 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('$q',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          _StepperButton(icon: Icons.add_rounded, onTap: () => _setQty(i, q + 1)),
          IconButton(
            tooltip: 'Quitar',
            onPressed: () => _remove(i),
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
          ),
        ]),
      ),
    );
  }

  Widget _sendBar() => Container(
        decoration: const BoxDecoration(
          color: AppUI.pageBg,
          border: Border(top: BorderSide(color: AppUI.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s12),
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.local_shipping_rounded, size: 20),
                label: Text('Enviar al proveedor (${_lines.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
        ),
      );

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
      radius: 24,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
        ),
        child: Icon(icon, size: 18, color: AppTheme.primary),
      ),
    );
  }
}
