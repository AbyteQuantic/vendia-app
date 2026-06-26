// Spec: specs/031-cotizaciones/spec.md
//
// Pantalla "Nueva cotización" / "Editar cotización" (F031 — AC-03).
//
// El dueño arma una cotización con:
//   - Cliente (obligatorio — reusa CustomerSelectorSheet de F030).
//   - Líneas de items: productos del inventario (selector) o líneas
//     libres escritas a mano (nombre + cantidad + precio).
//   - Descuento total opcional.
//   - Impuesto (tax) — solo si F023 (IVA) está ON, con la tasa local.
//   - Vigencia — date picker, default hoy + 15 días.
//   - Nota libre.
//
// Al guardar llama a `createQuote` (nueva) o `updateQuote` (editar). El
// backend asigna el folio y los totales; al editar una `enviada` el
// backend crea la V2.
//
// Gerontodiseño: textos ≥17pt, objetivos táctiles ≥48dp, 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/quote.dart';
import '../../models/quote_item.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/tax_settings_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import '../../widgets/product_picker_sheet.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../customers/customer_selector_sheet.dart';
import 'quote_capability_screen.dart'
    show kQuoteDefaultValidityDaysKey, kQuoteDefaultValidityDaysFallback;

class QuoteFormScreen extends StatefulWidget {
  /// Cotización a editar. Null → crear una nueva.
  final Quote? existing;

  /// Inyectable para tests — en producción se usa el ApiService default.
  final ApiService? apiOverride;

  /// Inyectable para tests — fuerza el estado de IVA sin SharedPreferences.
  /// Null → se usa `TaxSettingsService.instance`.
  final TaxSettingsService? taxServiceOverride;

  const QuoteFormScreen({
    super.key,
    this.existing,
    this.apiOverride,
    this.taxServiceOverride,
  });

  @override
  State<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends State<QuoteFormScreen> {
  late final ApiService _api;
  late final TaxSettingsService _tax;

  // Cliente elegido (F030).
  String? _customerId;
  String _customerName = '';

  // Líneas de la cotización.
  final List<QuoteItem> _items = [];

  final _discountCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();

  // Default sobrescrito en initState con la preferencia que guarda
  // QuoteCapabilityScreen (F040). Si no hay preferencia, queda en 15
  // (fallback histórico, kQuoteDefaultValidityDaysFallback).
  DateTime _validUntil = DateTime.now().add(const Duration(days: 15));

  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  /// True si la capacidad de impuestos (F023) está activa.
  bool get _taxEnabled => _tax.enabled;

  /// Tasa de impuesto vigente (0 cuando F023 está OFF).
  double get _taxRate => _taxEnabled ? _tax.rate : 0;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _tax = widget.taxServiceOverride ?? TaxSettingsService.instance;

    final existing = widget.existing;
    if (existing != null) {
      _customerId = existing.customerId;
      _customerName = existing.customerName;
      _items.addAll(existing.items);
      _discountCtrl.text = existing.discountTotal.round().toString();
      _noteCtrl.text = existing.note;
      if (existing.validUntil != null) _validUntil = existing.validUntil!;
    } else {
      // Cotización nueva: respetar el default que el tendero configuró
      // en QuoteCapabilityScreen (F040). Es async — si llega tarde, el
      // usuario ve 15 días primero y luego se actualiza al elegido.
      // En la práctica SharedPreferences resuelve en <50ms del primer
      // frame, así que el "salto" no es perceptible.
      _loadDefaultValidity();
    }
  }

  Future<void> _loadDefaultValidity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final days = prefs.getInt(kQuoteDefaultValidityDaysKey) ??
          kQuoteDefaultValidityDaysFallback;
      if (!mounted) return;
      setState(() {
        _validUntil = DateTime.now().add(Duration(days: days));
      });
    } catch (_) {
      // Fallback al hardcoded — ya está aplicado.
    }
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── Totales en vivo ────────────────────────────────────────────────

  double get _subtotal =>
      _items.fold(0.0, (sum, it) => sum + it.computedSubtotal);

  double get _discount {
    final raw = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    return raw < 0 ? 0 : raw;
  }

  /// Base imponible: subtotal menos descuento total (nunca negativa).
  double get _taxableBase {
    final base = _subtotal - _discount;
    return base < 0 ? 0 : base;
  }

  double get _taxAmount => _taxableBase * _taxRate;

  double get _total => _taxableBase + _taxAmount;

  // ── Cliente ────────────────────────────────────────────────────────

  Future<void> _pickCustomer() async {
    HapticFeedback.lightImpact();
    final customer = await showCustomerSelectorSheet(
      context,
      apiOverride: widget.apiOverride,
    );
    if (customer != null && mounted) {
      setState(() {
        _customerId = customer.id;
        _customerName = customer.name;
      });
    }
  }

  // ── Items ──────────────────────────────────────────────────────────

  Future<void> _addInventoryItem() async {
    HapticFeedback.lightImpact();
    final product = await showProductPicker(context, api: _api);
    if (product != null && mounted) {
      setState(() {
        _items.add(QuoteItem(
          productId: product.uuid,
          name: product.name,
          quantity: 1,
          unitPrice: product.price,
          sortOrder: _items.length,
        ));
      });
    }
  }

  Future<void> _addFreeLine() async {
    HapticFeedback.lightImpact();
    final line = await showModalBottomSheet<QuoteItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FreeLineSheet(),
    );
    if (line != null && mounted) {
      setState(() {
        _items.add(line.copyWith(sortOrder: _items.length));
      });
    }
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() => _items.removeAt(index));
  }

  void _updateItemQuantity(int index, double quantity) {
    if (quantity <= 0) return;
    setState(() {
      _items[index] = _items[index].copyWith(quantity: quantity);
    });
  }

  // ── Vigencia ───────────────────────────────────────────────────────

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Vigencia de la cotización',
    );
    if (picked != null && mounted) {
      setState(() => _validUntil = picked);
    }
  }

  // ── Guardar ────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_customerId == null || _customerId!.isEmpty) {
      _snack('Elija un cliente para la cotización', isError: true);
      HapticFeedback.heavyImpact();
      return;
    }
    if (_items.isEmpty) {
      _snack('Agregue al menos una línea a la cotización', isError: true);
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final payload = <String, dynamic>{
      'customer_id': _customerId,
      'items': _items.map((e) => e.toJson()).toList(),
      'discount_total': _discount,
      'tax_rate': _taxRate,
      // `.toUtc()` es OBLIGATORIO: el backend Go parsea las fechas como
      // RFC3339, que EXIGE zona horaria. Un DateTime local serializa sin
      // 'Z' ("2026-06-30T00:00:00.000") y el parse falla con 400 — por eso
      // NUNCA se pudo guardar una cotización. Eventos ya usaban .toUtc().
      'valid_until': _validUntil.toUtc().toIso8601String(),
      'note': _noteCtrl.text.trim(),
    };

    try {
      final Map<String, dynamic> res;
      if (_isEditing) {
        res = await _api.updateQuote(widget.existing!.id, payload);
      } else {
        res = await _api.createQuote(payload);
      }
      final saved = Quote.fromJson(res);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Mostramos el motivo real cuando el backend manda uno accionable
      // (validación), en vez de un genérico que oculta la causa.
      final msg = e is AppError && e.message.trim().isNotEmpty
          ? e.message
          : 'No se pudo guardar la cotización';
      debugPrint('[QUOTE] save failed: $e');
      _snack(msg, isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
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
          _isEditing ? 'Editar cotización' : 'Nueva cotización',
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _customerSection(),
            const SizedBox(height: 20),
            _itemsSection(),
            const SizedBox(height: 20),
            _discountSection(),
            const SizedBox(height: 20),
            _validitySection(),
            const SizedBox(height: 20),
            _noteSection(),
            const SizedBox(height: 20),
            _totalsCard(),
          ],
        ),
      ),
      bottomNavigationBar: _saveBar(),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      );

  Widget _customerSection() {
    final hasCustomer = _customerId != null && _customerId!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Cliente'),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const Key('quote_form_pick_customer'),
            borderRadius: BorderRadius.circular(16),
            onTap: _pickCustomer,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded,
                      color: AppTheme.primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasCustomer ? _customerName : 'Elegir cliente',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: hasCustomer
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.primary, size: 26),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Productos y servicios'),
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: const Text(
              'Aún no hay líneas. Agregue productos del inventario '
              'o líneas libres.',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
          )
        else
          ListView.separated(
            key: const Key('quote_form_items_list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ItemCard(
              index: i,
              item: _items[i],
              onRemove: () => _removeItem(i),
              onQuantityChanged: (q) => _updateItemQuantity(i, q),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('quote_form_add_inventory'),
                onPressed: _addInventoryItem,
                icon: const Icon(Icons.inventory_2_rounded, size: 20),
                label: const Text(
                  'Del inventario',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('quote_form_add_free'),
                onPressed: _addFreeLine,
                icon: const Icon(Icons.edit_rounded, size: 20),
                label: const Text(
                  'Línea libre',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _discountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Descuento total'),
        TextField(
          key: const Key('quote_form_discount'),
          controller: _discountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 18),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: '\$ ',
            hintText: '0',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _validitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Vigencia'),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const Key('quote_form_validity'),
            borderRadius: BorderRadius.circular(14),
            onTap: _pickValidUntil,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded,
                      color: AppTheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Válida hasta ${_formatDate(_validUntil)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary, size: 22),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _noteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Nota (opcional)'),
        TextField(
          key: const Key('quote_form_note'),
          controller: _noteCtrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            hintText: 'Ej: incluye instalación, entrega en 3 días',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          _totalRow('Subtotal', _subtotal),
          if (_discount > 0) _totalRow('Descuento', -_discount),
          if (_taxEnabled)
            _totalRow(
                'IVA (${(_taxRate * 100).round()}%)', _taxAmount),
          const Divider(height: 20),
          _totalRow('Total', _total, emphasize: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 20 : 16,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            // Formato correcto para negativos (descuento): "-$200", no el
            // "$-.200" que producía formatCOP con el signo adentro.
            amount < 0 ? '-${formatCOP(-amount)}' : formatCOP(amount),
            style: TextStyle(
              fontSize: emphasize ? 20 : 16,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('quote_form_save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : const Icon(Icons.check_rounded, size: 24),
            label: Text(
              _saving ? 'Guardando...' : 'Guardar cotización',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

/// Tarjeta de una línea de la cotización en el formulario.
///
/// Layout en DOS filas (concilio 2026-06-13, anti-overflow a 360dp):
///   Fila 1 — identidad: ícono + nombre (Expanded, ellipsis) + papelera.
///   Fila 2 — control: stepper [− N +] a la izquierda + "× precio" y el
///            subtotal a la derecha (Flexible). Tocar el número abre un
///            teclado numérico para escribir cantidades grandes (24, 100)
///            sin tocar [+] veinticuatro veces (gerontodiseño 50+).
class _ItemCard extends StatelessWidget {
  final int index;
  final QuoteItem item;
  final VoidCallback onRemove;
  final ValueChanged<double> onQuantityChanged;

  const _ItemCard({
    required this.index,
    required this.item,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  String get _qtyLabel =>
      item.quantity % 1 == 0 ? '${item.quantity.toInt()}' : '${item.quantity}';

  /// Abre un diálogo con teclado numérico para fijar la cantidad de un
  /// golpe (el valor llega preseleccionado para sobrescribir).
  Future<void> _promptQuantity(BuildContext context) async {
    final ctrl = TextEditingController(text: _qtyLabel)
      ..selection = TextSelection(baseOffset: 0, extentOffset: _qtyLabel.length);
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cantidad', style: TextStyle(fontSize: 20)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(double.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(ctrl.text.trim())),
            child: const Text('Listo', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    // Validación: rechazar vacío/no-numérico/<=0 (el padre tiene una segunda
    // barrera con `quantity <= 0`).
    if (result != null && result > 0) onQuantityChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final canDecrement = item.quantity > 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fila 1: identidad ──────────────────────────────────────
          Row(
            children: [
              Icon(
                item.isInventoryItem
                    ? Icons.inventory_2_rounded
                    : Icons.edit_note_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: Key('quote_line_remove_$index'),
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: AppTheme.error, size: 24),
                tooltip: 'Quitar de la cotización',
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Fila 2: stepper + subtotal ─────────────────────────────
          Row(
            children: [
              _QtyStepper(
                index: index,
                label: _qtyLabel,
                canDecrement: canDecrement,
                onDecrement: canDecrement
                    ? () => onQuantityChanged(item.quantity - 1)
                    : null,
                onIncrement: () => onQuantityChanged(item.quantity + 1),
                onEdit: () => _promptQuantity(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatCOP(item.computedSubtotal),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '× ${formatCOP(item.unitPrice)} c/u',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stepper táctil [− N +] para 50+. Botones grandes (48dp); el número
/// central es tocable y abre el teclado numérico (cantidades grandes).
class _QtyStepper extends StatelessWidget {
  final int index;
  final String label;
  final bool canDecrement;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onEdit;

  const _QtyStepper({
    required this.index,
    required this.label,
    required this.canDecrement,
    required this.onDecrement,
    required this.onIncrement,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            key: Key('quote_line_dec_$index'),
            icon: Icons.remove_rounded,
            tooltip: 'Disminuir cantidad',
            enabled: canDecrement,
            onTap: onDecrement,
          ),
          // Número tocable → teclado numérico para saltos grandes.
          InkWell(
            key: Key('quote_line_qty_$index'),
            onTap: onEdit,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          _stepButton(
            key: Key('quote_line_inc_$index'),
            icon: Icons.add_rounded,
            tooltip: 'Aumentar cantidad',
            enabled: true,
            onTap: onIncrement,
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 24,
            color: enabled ? AppTheme.primary : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet que lista los productos del inventario para elegir uno.
/// Bottom-sheet para crear una línea libre (nombre + cantidad + precio).
class _FreeLineSheet extends StatefulWidget {
  const _FreeLineSheet();

  @override
  State<_FreeLineSheet> createState() => _FreeLineSheetState();
}

class _FreeLineSheetState extends State<_FreeLineSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    Navigator.of(context).pop(QuoteItem(
      name: _nameCtrl.text.trim(),
      quantity: qty <= 0 ? 1 : qty,
      unitPrice: price,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D0C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Línea libre',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Descripción',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('free_line_name'),
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 18),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Ej: Mano de obra',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Ingrese una descripción';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cantidad',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const Key('free_line_qty'),
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              hintText: '1',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Precio',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const Key('free_line_price'),
                            controller: _priceCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              prefixText: '\$ ',
                              hintText: '0',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: (v) {
                              final n = double.tryParse(v?.trim() ?? '');
                              if (n == null || n <= 0) {
                                return 'Precio inválido';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('free_line_save'),
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: const Text('Agregar línea',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
