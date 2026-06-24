// Spec: specs/033-difusion-promociones/spec.md
//
// Pantalla "Crear / editar promoción" de difusión (F033 — spec §4,
// AC-03).
//
// Captura todos los campos de una campaña:
//   - Título y descripción.
//   - Foto / banner: subir desde galería O generar con IA (reusa el
//     generador Gemini `generatePromoBanner` ya en el ecosistema).
//   - Vigencia desde / hasta (default: hoy + 7 días).
//   - Items en oferta (opcional): productos del inventario con % de
//     descuento o precio fijo.
//   - Cupón informativo (opcional).
//   - Plantilla del mensaje de WhatsApp con placeholders.
//   - Programación: enviar ahora / mañana 9am / viernes 6pm.
//
// Al guardar, llama a `createBroadcastPromotion` / `updateBroadcastPromotion`
// y devuelve la BroadcastPromotion resultante al llamador.
//
// Gerontodiseño: inputs grandes, textos ≥17pt, táctil ≥48dp, 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/broadcast_promotion.dart';
import '../../models/promotion_item.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/promotion_scheduler.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/picked_image_preview.dart';

class PromotionFormScreen extends StatefulWidget {
  /// Promoción a editar. Null → crear una nueva.
  final BroadcastPromotion? existing;

  /// Inyectable para tests.
  final ApiService? apiOverride;

  /// Inyectable para tests — selector de imagen de galería.
  final Future<XFile?> Function()? imagePickerOverride;

  const PromotionFormScreen({
    super.key,
    this.existing,
    this.apiOverride,
    this.imagePickerOverride,
  });

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  late final ApiService _api;
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  DateTime _validFrom = DateTime.now();
  DateTime _validUntil = DateTime.now().add(const Duration(days: 7));

  /// URL del banner ya subido / generado.
  String _imageUrl = '';

  /// Imagen recién elegida en galería, aún no subida.
  XFile? _pickedImage;

  /// Items en oferta seleccionados.
  final List<PromotionItem> _items = [];

  PromotionSchedule _schedule = PromotionSchedule.now;

  bool _saving = false;
  bool _generatingBanner = false;
  bool _uploadingImage = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _couponCtrl.text = e.couponCode;
      _messageCtrl.text = e.messageTemplate;
      _imageUrl = e.imageUrl;
      _validFrom = e.validFrom ?? _validFrom;
      _validUntil = e.validUntil ?? _validUntil;
      _items.addAll(e.items);
    } else {
      // Default del mensaje — el dueño puede editarlo. Usa el
      // placeholder de primer nombre (spec §4.5).
      _messageCtrl.text =
          'Hola {primer_nombre} 👋 Tenemos una promo para usted 👇';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _couponCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  // ── Foto / banner ──────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    HapticFeedback.lightImpact();
    try {
      final picker = widget.imagePickerOverride ??
          () => ImagePicker().pickImage(source: ImageSource.gallery);
      final picked = await picker();
      if (picked == null) return;
      setState(() {
        _pickedImage = picked;
        _uploadingImage = true;
      });
      final res = await _api.uploadPromotionImage(picked);
      if (!mounted) return;
      setState(() {
        _imageUrl = (res['image_url'] as String?) ??
            (res['url'] as String?) ??
            '';
        _uploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _snack('No se pudo subir la imagen');
    }
  }

  Future<void> _generateBanner() async {
    HapticFeedback.lightImpact();
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Escriba primero el título de la promoción');
      return;
    }
    setState(() => _generatingBanner = true);
    try {
      final res = await _api.generatePromoBanner(
        promoName: title,
        productNames: _items.map((i) => i.productName).toList(),
        discountText: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _imageUrl = (res['image_url'] as String?) ??
            (res['banner_url'] as String?) ??
            (res['url'] as String?) ??
            '';
        _pickedImage = null;
        _generatingBanner = false;
      });
      if (_imageUrl.isEmpty) _snack('La IA no devolvió una imagen');
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingBanner = false);
      _snack('No se pudo generar el banner');
    }
  }

  // ── Vigencia ───────────────────────────────────────────────────

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _validFrom : _validUntil;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _validFrom = picked;
        if (_validUntil.isBefore(_validFrom)) {
          _validUntil = _validFrom.add(const Duration(days: 7));
        }
      } else {
        _validUntil = picked;
      }
    });
  }

  // ── Items en oferta ────────────────────────────────────────────

  Future<void> _addItem() async {
    HapticFeedback.lightImpact();
    final added = await showModalBottomSheet<PromotionItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemPickerSheet(api: _api),
    );
    if (added != null && mounted) {
      setState(() => _items.add(added));
    }
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() => _items.removeAt(index));
  }

  // ── Guardar ────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() {
      _saving = true;
      _error = null;
    });

    final scheduledFor = resolveSchedule(_schedule);
    final promo = BroadcastPromotion(
      id: widget.existing?.id ?? '',
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      imageUrl: _imageUrl,
      couponCode: _couponCtrl.text.trim(),
      validFrom: _validFrom,
      validUntil: _validUntil,
      messageTemplate: _messageCtrl.text.trim(),
      scheduledFor: scheduledFor,
      items: _items,
    );

    try {
      final Map<String, dynamic> res;
      if (_isEditing) {
        res = await _api.updateBroadcastPromotion(
            widget.existing!.id, promo.toJson());
      } else {
        res = await _api.createBroadcastPromotion(promo.toJson());
      }
      if (!mounted) return;
      Navigator.of(context).pop(BroadcastPromotion.fromJson(res));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar la promoción';
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(
          _isEditing ? 'Editar promoción' : 'Nueva promoción',
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _label('Título de la promoción'),
              TextFormField(
                key: const Key('promo_title'),
                controller: _titleCtrl,
                maxLength: 200,
                style: const TextStyle(fontSize: 17),
                decoration: _inputDecoration(
                    'Ej: 20% en kits de baño hasta el viernes'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escriba un título'
                    : null,
              ),
              _label('Descripción'),
              TextFormField(
                key: const Key('promo_description'),
                controller: _descCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 17),
                decoration:
                    _inputDecoration('Cuente de qué se trata la promo'),
              ),
              const SizedBox(height: 16),
              _label('Foto / banner'),
              _buildImageSection(),
              const SizedBox(height: 16),
              _label('Vigencia'),
              _buildDateRow(),
              const SizedBox(height: 16),
              _buildItemsSection(),
              const SizedBox(height: 16),
              _label('Cupón (opcional)'),
              TextFormField(
                key: const Key('promo_coupon'),
                controller: _couponCtrl,
                maxLength: 30,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 17),
                decoration: _inputDecoration('Ej: PROMO20'),
              ),
              _label('Mensaje de WhatsApp'),
              const Text(
                'Use {primer_nombre} o {nombre} y VendIA lo reemplaza '
                'por el nombre de cada cliente.',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('promo_message_template'),
                controller: _messageCtrl,
                maxLines: 4,
                style: const TextStyle(fontSize: 17),
                decoration: _inputDecoration(
                    'Hola {primer_nombre} 👋 …'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escriba el mensaje'
                    : null,
              ),
              const SizedBox(height: 16),
              _label('¿Cuándo enviar?'),
              _buildScheduleSelector(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  key: const Key('promo_save_button'),
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          _isEditing
                              ? 'Guardar cambios'
                              : 'Crear promoción',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final busy = _generatingBanner || _uploadingImage;
    return Column(
      children: [
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : _pickedImage != null
                  ? PickedImagePreview(file: _pickedImage!)
                  : _imageUrl.isNotEmpty
                      ? Image.network(
                          _imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('promo_pick_image'),
                onPressed: busy ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library_rounded, size: 20),
                label: const Text('Subir foto',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('promo_generate_banner'),
                onPressed: busy ? null : _generateBanner,
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                label: const Text('Generar con IA',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 4),
          Text(
            'Sin foto todavía',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(
          child: _DateField(
            fieldKey: const Key('promo_valid_from'),
            label: 'Desde',
            value: _fmtDate(_validFrom),
            onTap: () => _pickDate(isFrom: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DateField(
            fieldKey: const Key('promo_valid_until'),
            label: 'Hasta',
            value: _fmtDate(_validUntil),
            onTap: () => _pickDate(isFrom: false),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Items en oferta (opcional)',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton.icon(
              key: const Key('promo_add_item'),
              onPressed: _addItem,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Agregar',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No agregó productos en oferta.',
              style: TextStyle(
                  fontSize: 15, color: AppTheme.textSecondary),
            ),
          )
        else
          ...List.generate(_items.length, (i) {
            final item = _items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            item.mode == PromotionDiscountMode.percentage
                                ? '${item.discountPct?.toStringAsFixed(0)}% de descuento'
                                : 'Precio promo: \$${item.promoPrice?.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: Key('promo_remove_item_$i'),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppTheme.error),
                      onPressed: () => _removeItem(i),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildScheduleSelector() {
    return Wrap(
      spacing: 8,
      children: PromotionSchedule.values.map((s) {
        final selected = _schedule == s;
        return ChoiceChip(
          key: Key('promo_schedule_${s.name}'),
          label: Text(
            s.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
          selected: selected,
          showCheckmark: false,
          backgroundColor: Colors.white,
          selectedColor: AppTheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.borderColor),
          ),
          onSelected: (_) {
            HapticFeedback.selectionClick();
            setState(() => _schedule = s);
          },
        );
      }).toList(),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

/// Campo de fecha de solo lectura — abre el date picker al tocar.
class _DateField extends StatelessWidget {
  final Key fieldKey;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: fieldKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
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

/// Bottom-sheet para elegir un producto del inventario y su descuento.
class _ItemPickerSheet extends StatefulWidget {
  final ApiService api;

  const _ItemPickerSheet({required this.api});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  /// Producto elegido (raw json).
  Map<String, dynamic>? _selected;

  /// Modo de descuento.
  PromotionDiscountMode _mode = PromotionDiscountMode.percentage;
  final _valueCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.fetchProducts(perPage: 200);
      final raw = (res['data'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _products = raw.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _confirm() {
    final selected = _selected;
    if (selected == null) return;
    final value = double.tryParse(_valueCtrl.text.trim());
    if (value == null || value <= 0) return;
    final originalPrice =
        (selected['price'] as num? ?? 0).toDouble();
    final item = PromotionItem(
      productId: (selected['uuid'] ?? selected['id'] ?? '').toString(),
      productName: (selected['name'] as String?) ?? '',
      originalPrice: originalPrice,
      promoPrice:
          _mode == PromotionDiscountMode.fixedPrice ? value : null,
      discountPct:
          _mode == PromotionDiscountMode.percentage ? value : null,
    );
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agregar item en oferta',
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      key: const Key('item_picker_list'),
                      itemCount: _products.length,
                      itemBuilder: (_, i) {
                        final p = _products[i];
                        final id =
                            (p['uuid'] ?? p['id'] ?? '').toString();
                        final selectedId = (_selected?['uuid'] ??
                                _selected?['id'] ??
                                '')
                            .toString();
                        final isSelected =
                            _selected != null && selectedId == id;
                        return ListTile(
                          key: Key('item_picker_option_$id'),
                          onTap: () => setState(() => _selected = p),
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                          title: Text(
                            (p['name'] as String?) ?? 'Producto',
                            style: const TextStyle(fontSize: 16),
                          ),
                        );
                      },
                    ),
            ),
            if (_selected != null) ...[
              const Divider(),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('% descuento'),
                    selected:
                        _mode == PromotionDiscountMode.percentage,
                    onSelected: (_) => setState(() =>
                        _mode = PromotionDiscountMode.percentage),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Precio fijo'),
                    selected:
                        _mode == PromotionDiscountMode.fixedPrice,
                    onSelected: (_) => setState(() =>
                        _mode = PromotionDiscountMode.fixedPrice),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('item_value_field'),
                controller: _valueCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(
                  hintText:
                      _mode == PromotionDiscountMode.percentage
                          ? 'Ej: 20'
                          : 'Ej: 4000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const Key('item_confirm'),
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Agregar',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
