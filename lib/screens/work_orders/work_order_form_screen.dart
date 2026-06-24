// Spec: specs/003-trabajos-muebles/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../models/work_order.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'work_order_dialogs.dart';
import 'work_order_footer.dart';
import 'work_order_widgets.dart';

/// Formulario de alta/edición/detalle de un trabajo (Feature 003).
///
/// Cero fricción (Art. I): el tendero escoge un cliente, indica el tipo,
/// describe el encargo y agrega ítems de material y mano de obra. El
/// total se calcula solo. El trabajo nace en `cotizacion`.
///
/// Sobre un trabajo existente la pantalla es también el detalle: muestra
/// el ciclo de vida, deja avanzar el estado y cancelar, registrar
/// anticipos y compartir la cotización por WhatsApp. Los ítems solo se
/// editan en `cotizacion`/`aprobada` (FR-07, AC-07).
class WorkOrderFormScreen extends StatefulWidget {
  /// Trabajo a editar/ver; `null` crea uno nuevo.
  final WorkOrder? existing;

  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const WorkOrderFormScreen({super.key, this.existing, this.api});

  @override
  State<WorkOrderFormScreen> createState() => _WorkOrderFormScreenState();
}

class _WorkOrderFormScreenState extends State<WorkOrderFormScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  /// `id → nombre` de los clientes del tenant.
  final Map<String, String> _customers = {};

  /// Insumos y productos disponibles para agregar como material.
  final List<WorkMaterialSource> _sources = [];

  String? _customerId;
  String _type = WorkOrder.typeManufacture;
  List<WorkOrderItem> _items = [];

  /// Estado vivo del trabajo: cambia al avanzar el ciclo de vida o
  /// registrar anticipos sin salir de la pantalla.
  WorkOrder? _order;

  bool _loading = true;
  bool _saving = false;
  bool _busy = false;
  String? _loadError;
  String? _formError;

  bool get _isEditing => _order != null;

  /// Los ítems solo se editan en `cotizacion`/`aprobada` (FR-07, AC-07).
  /// Un trabajo nuevo (sin `_order`) siempre es editable.
  bool get _itemsEditable => _order == null || _order!.isEditable;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _order = e;
      _customerId = e.customerId;
      _type = e.type;
      _items = List<WorkOrderItem>.from(e.items);
      _descCtrl.text = e.description;
      _notesCtrl.text = e.notes ?? '';
    }
    _loadCatalogs();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final customersBody = await _api.fetchCustomers(perPage: 200);
      final rawIngredients = await _api.fetchIngredients();
      final productsBody = await _api.fetchProducts(perPage: 200);
      if (!mounted) return;

      final customerList =
          (customersBody['data'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      final productList =
          (productsBody['data'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];

      setState(() {
        _customers
          ..clear()
          ..addEntries(customerList.map((c) => MapEntry(
                (c['id'] ?? c['uuid'] ?? '') as String,
                (c['name'] as String?) ?? 'Cliente',
              )));
        _sources
          ..clear()
          ..addAll(rawIngredients.map((i) => WorkMaterialSource(
                id: (i['id'] ?? i['uuid'] ?? '') as String,
                name: (i['name'] as String?) ?? 'Insumo',
                isIngredient: true,
                unitCost: (i['unit_cost'] as num?)?.toDouble() ?? 0,
              )))
          ..addAll(productList.map((p) => WorkMaterialSource(
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
        'Error al cargar clientes/insumos/productos',
        name: 'WorkOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _loadError = 'No pudimos cargar clientes y materiales.';
        _loading = false;
      });
    }
  }

  double get _total =>
      _items.fold<double>(0, (sum, it) => sum + it.lineTotal);

  // ── Edición de ítems ──────────────────────────────────────────────

  Future<void> _addMaterial() async {
    if (_sources.isEmpty) {
      _snack('Primero registre insumos o productos.', AppTheme.warning);
      return;
    }
    final source = await showModalBottomSheet<WorkMaterialSource>(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => WorkMaterialPickerSheet(sources: _sources),
    );
    if (source == null || !mounted) return;
    final item = await promptMaterialItem(context, source);
    if (item == null || !mounted) return;
    setState(() => _items = [..._items, item]);
  }

  Future<void> _addLabor() async {
    final item = await promptLaborItem(context);
    if (item == null || !mounted) return;
    setState(() => _items = [..._items, item]);
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      final next = List<WorkOrderItem>.from(_items)..removeAt(index);
      _items = next;
    });
  }

  // ── Guardar (crear / editar) ──────────────────────────────────────

  Future<void> _save() async {
    if (_customerId == null || _customerId!.isEmpty) {
      setState(() => _formError = 'Debe escoger un cliente para el trabajo');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      setState(() => _formError = 'Describa el trabajo a realizar');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _formError =
          'Agregue al menos un material o mano de obra');
      return;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });

    final wo = WorkOrder(
      uuid: _order?.uuid ?? const Uuid().v4(),
      customerId: _customerId!,
      type: _type,
      status: _order?.status ?? WorkOrder.statusQuote,
      description: _descCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      items: _items,
    );

    try {
      final Map<String, dynamic> result;
      if (_isEditing) {
        result = await _api.updateWorkOrder(wo.uuid, wo.toJson());
      } else {
        result = await _api.createWorkOrder(wo.toJson());
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      // Refresca el estado vivo con la respuesta del backend (trae los
      // totales calculados) para que la pantalla pase a modo detalle.
      setState(() {
        _order = WorkOrder.fromJson(result);
        _items = List<WorkOrderItem>.from(_order!.items);
        _saving = false;
      });
      _snack('Trabajo guardado', AppTheme.success);
    } catch (e, stack) {
      developer.log(
        'Error al guardar el trabajo',
        name: 'WorkOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No se pudo guardar el trabajo. Intente de nuevo.',
          AppTheme.error);
    }
  }

  // ── Transiciones del ciclo de vida (AC-05) ────────────────────────

  Future<void> _advance() async {
    final order = _order;
    if (order == null || _busy) return;
    final next = order.nextStatus;
    if (next == null) return;
    HapticFeedback.lightImpact();

    final isCompleting = next == WorkOrder.statusDone;
    final confirmed = await confirmWorkAction(
      context,
      title: 'Pasar a "${WorkOrder.statusLabels[next]}"',
      message: isCompleting
          ? 'Al terminar el trabajo, los materiales se descuentan de su '
              'inventario automáticamente. Esto no se puede deshacer.'
          : '¿Confirma que el trabajo pasa a '
              '"${WorkOrder.statusLabels[next]}"?',
      confirmLabel: 'Sí, continuar',
      confirmColor: AppTheme.primary,
    );
    if (confirmed != true || !mounted) return;
    await _patchStatus(next);
  }

  Future<void> _cancelOrder() async {
    final order = _order;
    if (order == null || _busy) return;
    HapticFeedback.lightImpact();
    final confirmed = await confirmWorkAction(
      context,
      title: 'Cancelar el trabajo',
      message: 'El trabajo quedará cancelado y ya no se podrá retomar. '
          '¿Está seguro?',
      confirmLabel: 'Sí, cancelar',
      confirmColor: AppTheme.error,
    );
    if (confirmed != true || !mounted) return;
    await _patchStatus(WorkOrder.statusCanceled);
  }

  Future<void> _patchStatus(String newStatus) async {
    final order = _order;
    if (order == null) return;
    // Defensa local: nunca disparamos una transición inválida (AC-05);
    // el backend la rechazaría igual, esto evita una llamada perdida.
    if (!WorkOrder.isValidTransition(order.status, newStatus)) {
      _snack('Esa transición no es válida.', AppTheme.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final result =
          await _api.updateWorkOrder(order.uuid, {'status': newStatus});
      if (!mounted) return;
      setState(() {
        _order = WorkOrder.fromJson(result);
        _items = List<WorkOrderItem>.from(_order!.items);
        _busy = false;
      });
      _snack('Trabajo actualizado: ${_order!.statusLabel}',
          AppTheme.success);
    } catch (e, stack) {
      developer.log(
        'Error al cambiar el estado del trabajo ${order.uuid}',
        name: 'WorkOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('No se pudo cambiar el estado del trabajo.', AppTheme.error);
    }
  }

  // ── Anticipos (AC-02) ─────────────────────────────────────────────

  Future<void> _addPayment() async {
    final order = _order;
    if (order == null || _busy) return;
    HapticFeedback.lightImpact();
    final input = await promptPayment(context, balance: order.balance);
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _api.addWorkOrderPayment(order.uuid, {
        'amount': input.amount,
        'method': input.method,
      });
      if (!mounted) return;
      setState(() {
        _order = WorkOrder.fromJson(result);
        _items = List<WorkOrderItem>.from(_order!.items);
        _busy = false;
      });
      _snack('Anticipo registrado', AppTheme.success);
    } catch (e, stack) {
      developer.log(
        'Error al registrar el anticipo del trabajo ${order.uuid}',
        name: 'WorkOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('No se pudo registrar el anticipo.', AppTheme.error);
    }
  }

  // ── Compartir cotización por WhatsApp (AC-06) ─────────────────────

  Future<void> _share() async {
    final order = _order;
    if (order == null || _busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final res = await _api.shareWorkOrder(order.uuid);
      final url = res['whatsapp_url'] as String?;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        _snack('No se pudo armar el enlace de WhatsApp.', AppTheme.warning);
      }
    } catch (e, stack) {
      developer.log(
        'Error al compartir la cotización ${order.uuid}',
        name: 'WorkOrderFormScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      _snack('No se pudo compartir la cotización.', AppTheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
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
    // El botón de volver devuelve `_isEditing` para que la lista
    // recargue cuando el trabajo se creó o cambió de estado.
    return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(_isEditing),
          ),
          title: Text(
            _isEditing ? 'Detalle del trabajo' : 'Nuevo trabajo',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          actions: [
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: BranchSelectorChip()),
            ),
            if (_order != null && _order!.canShare)
              IconButton(
                key: const Key('btn_share_work_order'),
                icon: const Icon(Icons.share_rounded,
                    color: AppTheme.primary, size: 26),
                tooltip: 'Compartir cotización',
                onPressed: _busy ? null : _share,
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
      return WorkOrderErrorState(
          message: _loadError!, onRetry: _loadCatalogs);
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_order != null) ...[
                  _statusBanner(),
                  const SizedBox(height: 24),
                ],
                _label('Cliente'),
                const SizedBox(height: 8),
                _customerDropdown(),
                const SizedBox(height: 24),
                _label('Tipo de trabajo'),
                const SizedBox(height: 8),
                _typeSelector(),
                const SizedBox(height: 24),
                _label('¿Qué hay que hacer?'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('field_work_description'),
                  controller: _descCtrl,
                  enabled: _itemsEditable,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 20, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Ej: mesa de comedor en madera de pino',
                  ),
                ),
                const SizedBox(height: 24),
                _itemsSection(),
                const SizedBox(height: 24),
                _label('Notas (opcional)'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('field_work_notes'),
                  controller: _notesCtrl,
                  enabled: _itemsEditable,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 20, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Ej: entregar en la casa del cliente',
                  ),
                ),
                if (_order != null && _order!.payments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _paymentsSection(),
                ],
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
        WorkOrderFooter(
          order: _order,
          computedTotal: _total,
          saving: _saving,
          busy: _busy,
          isEditing: _isEditing,
          onSave: _save,
          onAdvance: _advance,
          onAddPayment: _addPayment,
          onCancelOrder: _cancelOrder,
        ),
      ],
    );
  }

  /// Banner de estado del trabajo en modo detalle.
  Widget _statusBanner() {
    final order = _order!;
    final color = workOrderStatusColor(order.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Estado: ${order.statusLabel}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Materiales y mano de obra'),
        const SizedBox(height: 8),
        if (_itemsEditable)
          Row(
            children: [
              Expanded(
                child: _addButton(
                  keyValue: 'btn_add_material',
                  label: 'Material',
                  icon: Icons.inventory_2_rounded,
                  onPressed: _addMaterial,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _addButton(
                  keyValue: 'btn_add_labor',
                  label: 'Mano de obra',
                  icon: Icons.construction_rounded,
                  onPressed: _addLabor,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aún no hay materiales ni mano de obra en este trabajo.',
              style:
                  TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          )
        else
          ..._items.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WorkItemCard(
                  item: entry.value,
                  onRemove: _itemsEditable
                      ? () => _removeItem(entry.key)
                      : null,
                ),
              )),
      ],
    );
  }

  Widget _paymentsSection() {
    final order = _order!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Anticipos del cliente'),
        const SizedBox(height: 8),
        ...order.payments.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    workPaymentMethods[p.method] ?? p.method,
                    style: const TextStyle(
                        fontSize: 18, color: AppTheme.textSecondary),
                  ),
                  Text(
                    workOrderMoney(p.amount),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            )),
      ],
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

  Widget _addButton({
    required String keyValue,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        key: Key(keyValue),
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.primary, size: 22),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _customerDropdown() {
    final entries = _customers.entries.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('field_work_customer'),
          value: entries.any((e) => e.key == _customerId)
              ? _customerId
              : null,
          isExpanded: true,
          hint: const Text(
            'Escoja un cliente',
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
          onChanged: !_itemsEditable
              ? null
              : (val) {
                  if (val != null) {
                    HapticFeedback.selectionClick();
                    setState(() => _customerId = val);
                  }
                },
        ),
      ),
    );
  }

  Widget _typeSelector() {
    return Row(
      children: WorkOrder.typeLabels.entries.map((entry) {
        final selected = _type == entry.key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: entry.key == WorkOrder.typeManufacture ? 12 : 0,
            ),
            child: GestureDetector(
              onTap: !_itemsEditable
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      setState(() => _type = entry.key);
                    },
              child: Container(
                key: Key('chip_type_${entry.key}'),
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primaryLight.withValues(alpha: 0.15)
                      : AppTheme.surfaceGrey,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.borderColor,
                    width: selected ? 2.5 : 1.5,
                  ),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
