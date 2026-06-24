// Spec: specs/002-ordenes-compra/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/purchase_order.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'purchase_order_form_widgets.dart';

/// Formulario de alta/edición de una orden de compra (Feature 002).
///
/// Cero fricción (Art. I): el tendero escoge un proveedor, agrega ítems
/// (insumos o productos) con cantidad y costo, y guarda. El total se
/// calcula solo. La PO se crea en `borrador`; enviar y recibir se hacen
/// desde la lista. En edición solo se permite si la PO está en `borrador`
/// (plan §4) — si no, el formulario es de solo lectura.
class PurchaseOrderFormScreen extends StatefulWidget {
  /// Orden a editar; `null` crea una nueva.
  final PurchaseOrder? existing;

  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const PurchaseOrderFormScreen({super.key, this.existing, this.api});

  @override
  State<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  final _notesCtrl = TextEditingController();

  /// `id → nombre` de los proveedores del tenant.
  final Map<String, String> _suppliers = {};

  /// Insumos y productos disponibles para agregar como ítems.
  final List<PurchaseItemSource> _sources = [];

  String? _supplierId;
  List<PurchaseOrderItem> _items = [];

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _formError;

  /// La PO se edita solo en `borrador`; en otro estado es solo lectura.
  bool get _readOnly =>
      widget.existing != null && !widget.existing!.isEditable;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _supplierId = e.supplierId;
      _items = List<PurchaseOrderItem>.from(e.items);
      _notesCtrl.text = e.notes ?? '';
    }
    _loadCatalogs();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rawSuppliers = await _api.fetchSuppliers();
      final rawIngredients = await _api.fetchIngredients();
      final productsBody = await _api.fetchProducts(perPage: 200);
      if (!mounted) return;

      final productList =
          (productsBody['data'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];

      setState(() {
        _suppliers
          ..clear()
          ..addEntries(rawSuppliers.map((s) => MapEntry(
                (s['id'] ?? s['uuid'] ?? '') as String,
                (s['company_name'] as String?) ?? 'Proveedor',
              )));
        _sources
          ..clear()
          ..addAll(rawIngredients.map((i) => PurchaseItemSource(
                id: (i['id'] ?? i['uuid'] ?? '') as String,
                name: (i['name'] as String?) ?? 'Insumo',
                isIngredient: true,
                unitCost: (i['unit_cost'] as num?)?.toDouble() ?? 0,
              )))
          ..addAll(productList.map((p) => PurchaseItemSource(
                id: (p['id'] ?? p['uuid'] ?? '').toString(),
                name: (p['name'] as String?) ?? 'Producto',
                isIngredient: false,
                unitCost: (p['price'] as num?)?.toDouble() ?? 0,
              )));
        _loading = false;
      });
    } catch (e, stack) {
      // El error real se registra; nunca se silencia (Constitución).
      developer.log(
        'Error al cargar proveedores/insumos/productos',
        name: 'PurchaseOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _loadError = 'No pudimos cargar proveedores y productos.';
        _loading = false;
      });
    }
  }

  double get _total =>
      _items.fold<double>(0, (sum, it) => sum + it.lineTotal);

  String _money(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$ $buf';
  }

  /// Abre un bottom sheet para escoger un insumo/producto y luego pide
  /// cantidad y costo (UI_RULES §9 — listas largas en bottom sheet).
  Future<void> _addItem() async {
    if (_sources.isEmpty) {
      _snack('Primero registre insumos o productos.', AppTheme.warning);
      return;
    }
    final source = await showModalBottomSheet<PurchaseItemSource>(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => PurchaseSourcePickerSheet(sources: _sources),
    );
    if (source == null || !mounted) return;
    final item = await _promptQuantityCost(source);
    if (item == null || !mounted) return;
    setState(() => _items = [..._items, item]);
  }

  /// Diálogo que pide cantidad y costo unitario de un ítem.
  Future<PurchaseOrderItem?> _promptQuantityCost(
    PurchaseItemSource source, {
    PurchaseOrderItem? existing,
  }) async {
    final qtyCtrl = TextEditingController(
      text: existing != null ? _trim(existing.quantity) : '',
    );
    final costCtrl = TextEditingController(
      text: existing != null
          ? _trim(existing.unitCost)
          : (source.unitCost > 0 ? _trim(source.unitCost) : ''),
    );
    String? err;

    final result = await showDialog<PurchaseOrderItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(
            source.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cantidad',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                key: const Key('field_item_quantity'),
                controller: qtyCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  hintText: '0',
                  errorText: err,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Costo por unidad',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                key: const Key('field_item_cost'),
                controller: costCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  hintText: '0',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancelar',
                style:
                    TextStyle(fontSize: 18, color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              key: const Key('btn_confirm_item'),
              onPressed: () {
                final qty = _parse(qtyCtrl.text);
                final cost = _parse(costCtrl.text);
                if (qty <= 0 || cost <= 0) {
                  setLocal(() => err = 'Cantidad y costo deben ser mayores '
                      'que cero');
                  return;
                }
                Navigator.of(ctx).pop(PurchaseOrderItem(
                  uuid: existing?.uuid,
                  ingredientId: source.isIngredient ? source.id : null,
                  productId: source.isIngredient ? null : source.id,
                  nameSnapshot: source.name,
                  quantity: qty,
                  unitCost: cost,
                ));
              },
              child: const Text(
                'Agregar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Los controladores se liberan tras la animación de salida del
    // diálogo: disponerlos de inmediato los deja en uso por el
    // `AnimatedBuilder` del cierre y lanza "used after being disposed".
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      qtyCtrl.dispose();
      costCtrl.dispose();
    });
    return result;
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      final next = List<PurchaseOrderItem>.from(_items)..removeAt(index);
      _items = next;
    });
  }

  double _parse(String raw) {
    final clean = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _save() async {
    if (_supplierId == null || _supplierId!.isEmpty) {
      setState(() => _formError = 'Debe escoger un proveedor para el pedido');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _formError = 'Agregue al menos un producto al pedido');
      return;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });

    final po = PurchaseOrder(
      uuid: widget.existing?.uuid ?? const Uuid().v4(),
      supplierId: _supplierId!,
      status: PurchaseOrder.statusDraft,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      items: _items,
    );

    try {
      if (_isEditing) {
        await _api.updatePurchaseOrder(po.uuid, po.toJson());
      } else {
        await _api.createPurchaseOrder(po.toJson());
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      developer.log(
        'Error al guardar la orden de compra',
        name: 'PurchaseOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No se pudo guardar la orden. Intente de nuevo.',
          AppTheme.error);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _readOnly
              ? 'Detalle de la orden'
              : (_isEditing ? 'Editar orden' : 'Nueva orden'),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return PurchaseFormErrorState(message: _loadError!, onRetry: _loadCatalogs);
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Proveedor'),
                const SizedBox(height: 8),
                _supplierDropdown(),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _label('Productos del pedido'),
                    if (!_readOnly)
                      TextButton.icon(
                        key: const Key('btn_add_item'),
                        onPressed: _addItem,
                        icon: const Icon(Icons.add_rounded,
                            color: AppTheme.primary, size: 24),
                        label: const Text(
                          'Agregar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aún no hay productos en este pedido.',
                      style: TextStyle(
                          fontSize: 18, color: AppTheme.textSecondary),
                    ),
                  )
                else
                  ..._items.asMap().entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PurchaseItemCard(
                          item: entry.value,
                          money: _money,
                          trim: _trim,
                          onRemove: _readOnly
                              ? null
                              : () => _removeItem(entry.key),
                        ),
                      )),
                const SizedBox(height: 24),
                _label('Notas (opcional)'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('field_po_notes'),
                  controller: _notesCtrl,
                  enabled: !_readOnly,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 20, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Ej: entregar antes del mediodía',
                  ),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _formError!,
                    style: const TextStyle(
                        fontSize: 18, color: AppTheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: AppTheme.borderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total del pedido',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                _money(_total),
                key: const Key('text_po_total'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_readOnly)
            SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  key: const Key('btn_save_purchase_order'),
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEditing
                              ? 'Guardar cambios'
                              : 'Guardar orden',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            )
          else
            const SafeArea(
              minimum: EdgeInsets.only(bottom: 24),
              child: Text(
                'Esta orden ya no se puede editar.',
                style:
                    TextStyle(fontSize: 18, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      );

  Widget _supplierDropdown() {
    final entries = _suppliers.entries.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('field_po_supplier'),
          value: _supplierId,
          isExpanded: true,
          hint: const Text(
            'Escoja un proveedor',
            style: TextStyle(fontSize: 20, color: AppTheme.textSecondary),
          ),
          style: const TextStyle(
            fontSize: 20,
            color: AppTheme.textPrimary,
            fontFamily: 'Roboto',
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          items: entries
              .map((e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: _readOnly
              ? null
              : (val) {
                  if (val != null) {
                    HapticFeedback.selectionClick();
                    setState(() => _supplierId = val);
                  }
                },
        ),
      ),
    );
  }
}
