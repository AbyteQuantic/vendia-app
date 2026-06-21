// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Registrar el precio de un insumo CON su proveedor (Spec 077, claro y sin
/// confundir): PASO 1 elegir/registrar el proveedor; PASO 2 el precio. Así el
/// precio queda atado a un proveedor real (no a un texto suelto).
Future<bool?> showSupplierPriceEditor(
    BuildContext context, Map<String, dynamic> ingredient,
    {ApiService? api}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _SupplierPriceEditor(ingredient: ingredient, api: api),
  );
}

class _SupplierPriceEditor extends StatefulWidget {
  final Map<String, dynamic> ingredient;
  final ApiService? api;
  const _SupplierPriceEditor({required this.ingredient, this.api});

  @override
  State<_SupplierPriceEditor> createState() => _SupplierPriceEditorState();
}

class _SupplierPriceEditorState extends State<_SupplierPriceEditor> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  String _step = 'supplier'; // supplier | newSupplier | price
  String _supplierId = '';
  String _supplierName = '';
  bool _busy = false;

  final _newNameCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  String get _unit => (widget.ingredient['unit'] ?? '').toString();

  Future<void> _createSupplier() async {
    final name = _newNameCtrl.text.trim();
    final phone = _newPhoneCtrl.text.trim();
    if (name.isEmpty || phone.length < 7) return;
    setState(() => _busy = true);
    try {
      final res = await _api.createSupplier({'company_name': name, 'phone': phone});
      _supplierId = (res['id'] ?? '').toString();
      _supplierName = name;
      setState(() {
        _busy = false;
        _step = 'price';
      });
    } catch (_) {
      setState(() => _busy = false);
      _snack('No se pudo registrar el proveedor.');
    }
  }

  Future<void> _savePrice() async {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
    if (price <= 0) return;
    setState(() => _busy = true);
    try {
      await _api.addSupplyPrice(
        ingredientId: widget.ingredient['ingredient_id'].toString(),
        rawName: widget.ingredient['name'].toString(),
        unitPrice: price,
        supplierId: _supplierId,
        supplierName: _supplierName,
        packUnit: _unit,
      );
      if (!mounted) return;
      _snack('Precio guardado para $_supplierName.', ok: true);
      Navigator.pop(context, true);
    } catch (_) {
      setState(() => _busy = false);
      _snack('No se pudo guardar el precio.');
    }
  }

  void _snack(String m, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: ok ? AppTheme.success : AppTheme.error));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppUI.s16, right: AppUI.s16, top: AppUI.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppUI.s16,
      ),
      child: _busy
          ? const Padding(padding: EdgeInsets.all(AppUI.s24), child: Center(child: CircularProgressIndicator()))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.ingredient['name']} · precio de proveedor', style: AppUI.bodyStrong),
              const SizedBox(height: AppUI.s12),
              if (_step == 'supplier') _pickSupplier(),
              if (_step == 'newSupplier') _newSupplier(),
              if (_step == 'price') _priceForm(),
            ]),
    );
  }

  Widget _pickSupplier() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('PASO 1 · ¿A qué proveedor?', style: AppUI.sectionLabel),
      const SizedBox(height: 4),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _api.fetchSuppliers(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(AppUI.s16), child: Center(child: CircularProgressIndicator()));
          final list = snap.data!;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((e['company_name'] ?? e['name'] ?? '').toString(), style: AppUI.bodyStrong),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
                onTap: () {
                  _supplierId = (e['id'] ?? '').toString();
                  _supplierName = (e['company_name'] ?? e['name'] ?? '').toString();
                  setState(() => _step = 'price');
                },
              ),
            const SizedBox(height: AppUI.s8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              key: const Key('register_new_supplier'),
              onPressed: () => setState(() => _step = 'newSupplier'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Registrar proveedor nuevo'),
            )),
          ]);
        },
      ),
    ]);
  }

  Widget _newSupplier() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Nuevo proveedor', style: AppUI.sectionLabel),
      TextField(controller: _newNameCtrl, decoration: const InputDecoration(labelText: 'Nombre del proveedor')),
      TextField(controller: _newPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (WhatsApp)')),
      const SizedBox(height: AppUI.s12),
      SizedBox(width: double.infinity, child: ElevatedButton(
        key: const Key('save_new_supplier'),
        onPressed: _createSupplier,
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, elevation: 0),
        child: const Text('Continuar'),
      )),
    ]);
  }

  Widget _priceForm() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PASO 2 · Precio en $_supplierName', style: AppUI.sectionLabel),
      TextField(
        key: const Key('supplier_price_input'),
        controller: _priceCtrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Precio por $_unit (\$)'),
      ),
      const SizedBox(height: AppUI.s12),
      SizedBox(width: double.infinity, child: ElevatedButton(
        key: const Key('supplier_price_save'),
        onPressed: _savePrice,
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, elevation: 0),
        child: const Text('Guardar precio'),
      )),
    ]);
  }
}
