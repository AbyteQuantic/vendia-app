import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'promo_share_screen.dart';

/// 4-step wizard for building a combo promotion. Designed for the
/// 50+ audience — each step is a big, stand-alone card, financial
/// feedback is in large-font colour-coded text, and the "next" button
/// is always visible at the bottom.
///
/// When launched from the expiring-products alert, pass `seedProducts`
/// to pre-populate Step 1.
class PromoBuilderScreen extends StatefulWidget {
  final List<LocalProduct> seedProducts;

  const PromoBuilderScreen({super.key, this.seedProducts = const []});

  @override
  State<PromoBuilderScreen> createState() => _PromoBuilderScreenState();
}

enum _Validity { today, untilStockOut, customDate }

class _PromoLine {
  final LocalProduct product;
  int quantity;
  int promoPriceEach; // COP (integer cents would be overkill here)

  _PromoLine({
    required this.product,
    required this.quantity,
    required this.promoPriceEach,
  });
}

class _PromoBuilderScreenState extends State<PromoBuilderScreen> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _customDiscountCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<LocalProduct> _allProducts = [];
  List<LocalProduct> _searchResults = [];
  final bool _searching = false;

  final List<_PromoLine> _lines = [];

  _Validity _validity = _Validity.today;
  DateTime? _customEnd;
  int? _stockLimit;

  String? _bannerUrl;
  bool _generatingBanner = false;
  String _tone = 'vibrante';

  int _currentStep = 0; // 0..3
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _customDiscountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final all = await DatabaseService.instance.getAllProducts();
    if (!mounted) return;
    setState(() {
      _allProducts = all;
      _searchResults = all.take(30).toList();
    });
    for (final seed in widget.seedProducts) {
      if (!_lines.any((l) => l.product.uuid == seed.uuid)) {
        _lines.add(_buildLineFor(seed));
      }
    }
    if (widget.seedProducts.isNotEmpty) {
      _nameCtrl.text = 'Combo ${widget.seedProducts.first.name}';
    }
    if (mounted) setState(() {});
  }

  _PromoLine _buildLineFor(LocalProduct p) {
    // Default: one unit at 15% off (Colombian $50-rounded). The
    // shopkeeper can tweak — this just avoids a zero on first load.
    final suggested = ((p.price * 0.85) / 50).ceil() * 50;
    return _PromoLine(
      product: p,
      quantity: 1,
      promoPriceEach: suggested.toInt(),
    );
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      final lower = q.trim().toLowerCase();
      if (lower.isEmpty) {
        setState(() => _searchResults = _allProducts.take(30).toList());
        return;
      }
      setState(() {
        _searchResults = _allProducts
            .where((p) => p.name.toLowerCase().contains(lower))
            .take(30)
            .toList();
      });
    });
  }

  void _addLine(LocalProduct p) {
    HapticFeedback.lightImpact();
    if (_lines.any((l) => l.product.uuid == p.uuid)) {
      _showToast('${p.name} ya está en el combo');
      return;
    }
    setState(() => _lines.add(_buildLineFor(p)));
  }

  void _removeLine(String uuid) {
    HapticFeedback.lightImpact();
    setState(() => _lines.removeWhere((l) => l.product.uuid == uuid));
  }

  // ── Financial math (mirrors backend calculatePromoFinancials) ──────────

  // LocalProduct doesn't carry purchase_price, so the on-device preview
  // uses price * 0.7 as an "estimated cost" with a clear label. Backend
  // authorises the real margin when the promo is saved. Good enough for
  // the shopkeeper's red/green gut-check while editing the combo.
  double get _estimatedCost =>
      _lines.fold(0.0, (sum, l) => sum + (l.product.price * 0.7) * l.quantity);

  double get _totalRegular => _lines.fold(
        0.0,
        (sum, l) => sum + (l.product.price * l.quantity),
      );

  double get _totalPromo => _lines.fold(
        0.0,
        (sum, l) => sum + (l.promoPriceEach * l.quantity).toDouble(),
      );

  double get _discountAmount => _totalRegular - _totalPromo;
  double get _discountPercent =>
      _totalRegular > 0 ? (_discountAmount / _totalRegular) * 100 : 0;
  double get _netProfit => _totalPromo - _estimatedCost;
  bool get _isProfitable => _netProfit >= 0;

  String _cop(num n) {
    final i = n.round();
    if (i == 0) return '\$0';
    final s = i.abs().toString();
    final buf = StringBuffer(i < 0 ? '-\$' : '\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i2 = start; i2 < s.length; i2 += 3) {
      if (i2 > 0) buf.write('.');
      buf.write(s.substring(i2, i2 + 3));
    }
    return buf.toString();
  }

  // ── Banner generation ──────────────────────────────────────────────────

  Future<void> _generateBanner() async {
    if (_lines.isEmpty || _nameCtrl.text.trim().isEmpty) {
      _showToast('Ponle un nombre al combo y agrega productos primero');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _generatingBanner = true);
    try {
      final api = ApiService(AuthService());
      final discountText = _customDiscountCtrl.text.trim().isNotEmpty
          ? _customDiscountCtrl.text.trim()
          : '${_discountPercent.round()}% OFF';
      final res = await api.generatePromoBanner(
        promoName: _nameCtrl.text.trim(),
        productNames: _lines.map((l) => l.product.name).toList(),
        discountText: discountText,
        tone: _tone,
      );
      final url = res['banner_url'] as String?;
      if (url != null && mounted) {
        setState(() => _bannerUrl = url);
      }
    } catch (e) {
      _showToast('No se pudo generar el banner: $e');
    } finally {
      if (mounted) setState(() => _generatingBanner = false);
    }
  }

  Future<void> _pickBannerFromGallery() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo != null && mounted) {
      setState(() => _bannerUrl = photo.path); // local path — upload later
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_lines.isEmpty || _nameCtrl.text.trim().isEmpty) {
      _showToast('Necesitas nombre y al menos un producto');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      final api = ApiService(AuthService());
      final promoId = const Uuid().v4();

      DateTime? endDate;
      if (_validity == _Validity.today) {
        final now = DateTime.now();
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (_validity == _Validity.customDate) {
        endDate = _customEnd;
      } // untilStockOut → null endDate, stock_limit carries it

      final payload = <String, dynamic>{
        'id': promoId,
        'name': _nameCtrl.text.trim(),
        'description': _customDiscountCtrl.text.trim(),
        'banner_image_url': _bannerUrl ?? '',
        'start_date': DateTime.now().toUtc().toIso8601String(),
        if (endDate != null) 'end_date': endDate.toUtc().toIso8601String(),
        if (_validity == _Validity.untilStockOut && _stockLimit != null)
          'stock_limit': _stockLimit,
        'items': _lines
            .map((l) => {
                  'product_id': l.product.uuid,
                  'quantity': l.quantity,
                  'promo_price': l.promoPriceEach,
                })
            .toList(),
      };

      await api.createPromotion(payload);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PromoShareScreen(
            promoName: _nameCtrl.text.trim(),
            bannerUrl: _bannerUrl,
            products: _lines.map((l) => l.product.name).toList(),
            totalPromo: _totalPromo,
          ),
        ),
      );
    } catch (e) {
      _showToast('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.textPrimary,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Crear promoción — Paso ${_currentStep + 1} de 4',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _stepperBar(),
            Expanded(child: _buildCurrentStep()),
            _bottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _stepperBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: List.generate(4, (i) {
          final active = i <= _currentStep;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppTheme.primary : AppTheme.borderColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _stepProducts();
      case 1:
        return _stepFinancialCalculator();
      case 2:
        return _stepValidity();
      case 3:
      default:
        return _stepCreative();
    }
  }

  // ── Step 1: Products ───────────────────────────────────────────────────

  Widget _stepProducts() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            labelText: 'Nombre del combo',
            hintText: 'Ej: Combo Desayuno, 2x1 Gaseosas',
            prefixIcon: Icon(Icons.local_offer_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(fontSize: 17),
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Buscar producto en inventario…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        if (_lines.isNotEmpty) ...[
          const Text('Productos en el combo',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          ..._lines.map(_lineChip),
          const SizedBox(height: 12),
        ],
        const Text('Inventario',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        ..._searchResults.map(_resultTile),
      ],
    );
  }

  Widget _lineChip(_PromoLine l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        border: Border.all(color: AppTheme.primary, width: 1.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.product.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Cantidad: ${l.quantity} · Precio normal: ${_cop(l.product.price)}',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded,
                color: AppTheme.error, size: 26),
            onPressed: () => _removeLine(l.product.uuid),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(LocalProduct p) {
    final already = _lines.any((l) => l.product.uuid == p.uuid);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: false,
      title: Text(p.name, style: const TextStyle(fontSize: 16)),
      subtitle: Text(_cop(p.price),
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
      trailing: already
          ? const Icon(Icons.check_circle_rounded, color: AppTheme.success)
          : IconButton(
              icon: const Icon(Icons.add_circle_rounded,
                  color: AppTheme.primary, size: 28),
              onPressed: () => _addLine(p),
            ),
    );
  }

  // ── Step 2: Financial Calculator ───────────────────────────────────────

  Widget _stepFinancialCalculator() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text(
          'Ajusta cantidad y precio de cada producto',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ..._lines.map(_lineEditor),
        const SizedBox(height: 16),
        _summaryCard(),
      ],
    );
  }

  Widget _lineEditor(_PromoLine l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.product.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Normal: ${_cop(l.product.price)}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _stepper(
                  label: 'Cantidad',
                  value: l.quantity,
                  onChanged: (v) => setState(() => l.quantity = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _priceInput(
                  label: 'Precio combo c/u',
                  value: l.promoPriceEach,
                  onChanged: (v) =>
                      setState(() => l.promoPriceEach = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  if (value > 1) {
                    HapticFeedback.lightImpact();
                    onChanged(value - 1);
                  }
                },
                child: const SizedBox(
                  width: 44,
                  child: Icon(Icons.remove_rounded),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('$value',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onChanged(value + 1);
                },
                child: Container(
                  width: 44,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(11)),
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _priceInput({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              prefixText: '\$ ',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    final profitColor =
        _isProfitable ? AppTheme.success : AppTheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: profitColor.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: profitColor.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Resumen financiero',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _summaryRow('Precio normal total', _cop(_totalRegular),
              color: AppTheme.textSecondary),
          _summaryRow('Costo estimado', _cop(_estimatedCost),
              color: AppTheme.textSecondary,
              small: true,
              hint: '*aprox. 70% del precio normal'),
          _summaryRow('Precio promo', _cop(_totalPromo),
              color: AppTheme.primary, bold: true),
          const Divider(height: 18),
          _summaryRow('Descuento otorgado',
              '${_cop(_discountAmount)}  (${_discountPercent.toStringAsFixed(1)}%)',
              color: AppTheme.warning, bold: true),
          _summaryRow(
            _isProfitable ? 'Utilidad neta' : '⚠️ Pérdida',
            _cop(_netProfit),
            color: profitColor,
            bold: true,
            big: true,
          ),
          if (!_isProfitable) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '⚠️ Esta promo te haría perder plata. Ajusta el precio hacia arriba o quita algún producto.',
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    required Color color,
    bool bold = false,
    bool big = false,
    bool small = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: small ? 13 : 15,
                      color: color,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    )),
                if (hint != null)
                  Text(hint,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Text(value,
              style: TextStyle(
                fontSize: big ? 22 : (small ? 13 : 16),
                color: color,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              )),
        ],
      ),
    );
  }

  // ── Step 3: Validity ──────────────────────────────────────────────────

  Widget _stepValidity() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text('¿Hasta cuándo estará activa la promoción?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        _radioCard(
          _Validity.today,
          title: 'Solo por hoy',
          subtitle: 'Vence a las 11:59 PM de hoy',
          icon: Icons.today_rounded,
        ),
        _radioCard(
          _Validity.untilStockOut,
          title: 'Hasta agotar inventario',
          subtitle: 'Define cuántos combos máximo',
          icon: Icons.inventory_2_rounded,
        ),
        if (_validity == _Validity.untilStockOut)
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 4, right: 8, bottom: 12),
            child: TextFormField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cantidad máxima de combos',
                hintText: 'Ej: 10',
              ),
              onChanged: (v) {
                _stockLimit = int.tryParse(v);
              },
            ),
          ),
        _radioCard(
          _Validity.customDate,
          title: 'Fecha personalizada',
          subtitle: _customEnd == null
              ? 'Toca para elegir una fecha'
              : 'Hasta ${_customEnd!.day}/${_customEnd!.month}/${_customEnd!.year}',
          icon: Icons.event_rounded,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _customEnd ?? now.add(const Duration(days: 7)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 365)),
              helpText: 'Vigencia hasta',
              confirmText: 'Listo',
              cancelText: 'Cancelar',
            );
            if (picked != null) {
              setState(() {
                _customEnd = picked;
                _validity = _Validity.customDate;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _radioCard(
    _Validity val, {
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final selected = _validity == val;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _validity = val);
        if (onTap != null) onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            // Using the legacy Radio params because the RadioGroup API
            // landed after our current Flutter pin; revisit on upgrade.
            // ignore: deprecated_member_use
            Radio<_Validity>(
              value: val,
              // ignore: deprecated_member_use
              groupValue: _validity,
              // ignore: deprecated_member_use
              onChanged: (_) => setState(() => _validity = val),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 4: Creative Studio ────────────────────────────────────────────

  Widget _stepCreative() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text('Estudio creativo',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Genera un banner publicitario con IA o súbelo desde tu galería.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _customDiscountCtrl,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: 'Texto grande del banner',
            hintText: 'Ej: 2x1 · Solo hoy · 30% OFF',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _toneChip('vibrante', '🎨 Vibrante'),
            _toneChip('elegante', '✨ Elegante'),
            _toneChip('urgente', '🔥 Urgente'),
          ],
        ),
        const SizedBox(height: 16),
        _bannerPreview(),
        const SizedBox(height: 14),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _generatingBanner ? null : _generateBanner,
            icon: _generatingBanner
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Icon(Icons.auto_awesome_rounded, size: 22),
            label: Text(
              _generatingBanner
                  ? 'Generando con IA…'
                  : '✨ Generar banner con IA',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _pickBannerFromGallery,
            icon: const Icon(Icons.photo_library_rounded),
            label: const Text('Subir foto desde galería',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary,
              side: const BorderSide(color: AppTheme.borderColor),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _toneChip(String value, String label) {
    final selected = _tone == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _tone = value),
        selectedColor: AppTheme.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: selected ? AppTheme.primary : AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _bannerPreview() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: _bannerUrl == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_outlined,
                          size: 56, color: AppTheme.textSecondary),
                      SizedBox(height: 8),
                      Text('Aquí aparecerá tu banner',
                          style: TextStyle(
                              fontSize: 15, color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : _bannerUrl!.startsWith('http') ||
                      _bannerUrl!.startsWith('data:')
                  ? Image.network(_bannerUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_rounded, size: 48))
                  : Image.asset(_bannerUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_rounded, size: 48)),
        ),
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────

  Widget _bottomNav() {
    final canAdvance = switch (_currentStep) {
      0 => _lines.isNotEmpty && _nameCtrl.text.trim().isNotEmpty,
      1 => _lines.isNotEmpty && _totalPromo > 0,
      2 => _validity != _Validity.customDate || _customEnd != null,
      _ => true,
    };

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Atrás',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 10),
          Expanded(
            flex: _currentStep == 3 ? 2 : 1,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: !canAdvance
                    ? null
                    : (_currentStep == 3
                        ? (_saving ? null : _save)
                        : () => setState(() => _currentStep++)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _currentStep == 3
                      ? (_saving ? 'Guardando…' : 'Guardar y compartir')
                      : 'Siguiente',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
