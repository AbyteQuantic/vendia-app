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

/// Tipo de promoción. Afecta el Paso 1 (cuántos productos se pueden
/// elegir), el Paso 2 (editor financiero) y la serialización a la API
/// (`promo_type`).
enum _PromoType {
  /// Varios productos juntos a precio especial (flujo original).
  combo,

  /// "Lleve X, Pague Y" sobre un mismo producto. Se serializa como
  /// un PromotionItem único con `quantity = buyQuantity` y
  /// `promo_price` igual al precio unitario efectivo — así el backend
  /// y el público lo interpretan como un combo de N unidades sin que
  /// tengamos que cambiar el schema.
  buyXPayY,
}

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

/// Resultado financiero puro de un "Lleva X, Paga Y". Expuesto como
/// top-level para poder testearlo sin montar el widget.
///
/// Convención:
///   * [unitPrice]  — precio normal de 1 unidad.
///   * [unitCost]   — costo estimado de 1 unidad (≈ 70% del precio).
///   * [buyQty]     — unidades que se lleva el cliente.
///   * [payQty]     — unidades que paga el cliente (buyQty > payQty).
///
/// Salidas:
///   * totalRegular = unitPrice * buyQty
///   * totalPromo   = unitPrice * payQty
///   * cost         = unitCost  * buyQty  (el tendero igual desembolsa X)
///   * netProfit    = totalPromo - cost
class BuyXPayYFinancials {
  final double totalRegular;
  final double totalPromo;
  final double cost;
  final double netProfit;
  final double discountAmount;
  final double discountPercent;
  final bool isProfitable;

  const BuyXPayYFinancials({
    required this.totalRegular,
    required this.totalPromo,
    required this.cost,
    required this.netProfit,
    required this.discountAmount,
    required this.discountPercent,
    required this.isProfitable,
  });

  factory BuyXPayYFinancials.compute({
    required double unitPrice,
    required double unitCost,
    required int buyQty,
    required int payQty,
  }) {
    final totalRegular = unitPrice * buyQty;
    final totalPromo = unitPrice * payQty;
    final cost = unitCost * buyQty;
    final netProfit = totalPromo - cost;
    final discountAmount = totalRegular - totalPromo;
    final discountPercent =
        totalRegular > 0 ? (discountAmount / totalRegular) * 100 : 0.0;
    return BuyXPayYFinancials(
      totalRegular: totalRegular,
      totalPromo: totalPromo,
      cost: cost,
      netProfit: netProfit,
      discountAmount: discountAmount,
      discountPercent: discountPercent,
      isProfitable: netProfit >= 0,
    );
  }
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

  // Promo type — controls both Step 1 (how many products can be added)
  // and Step 2 (which editor is shown). Default: classic combo.
  _PromoType _promoType = _PromoType.combo;

  // Buy X / Pay Y — only relevant when _promoType == buyXPayY.
  // "El cliente LLEVA _buyQty, PAGA _payQty". Both default to sensible
  // values so the summary card never shows NaN/0 divisions.
  int _buyQty = 3;
  int _payQty = 2;

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
      _showToast(_promoType == _PromoType.buyXPayY
          ? 'Ya elegiste este producto'
          : '${p.name} ya está en el combo');
      return;
    }
    // En modo "Lleve X, Pague Y" la promoción gira alrededor de UN
    // solo producto — el segundo tap sustituye al anterior en vez de
    // agregarlo (más predecible para el usuario que bloquear el tap).
    if (_promoType == _PromoType.buyXPayY) {
      setState(() {
        _lines
          ..clear()
          ..add(_buildLineFor(p));
      });
      return;
    }
    setState(() => _lines.add(_buildLineFor(p)));
  }

  /// Cambia el tipo de promoción. Si se pasa a BxPy y hay múltiples
  /// líneas, conserva solo la primera (no queremos perder el trabajo
  /// del usuario sin avisar, pero sí enforzar la regla del modo).
  void _setPromoType(_PromoType t) {
    if (t == _promoType) return;
    HapticFeedback.selectionClick();
    setState(() {
      _promoType = t;
      if (t == _PromoType.buyXPayY && _lines.length > 1) {
        _lines.removeRange(1, _lines.length);
      }
    });
  }

  void _removeLine(String uuid) {
    HapticFeedback.lightImpact();
    setState(() => _lines.removeWhere((l) => l.product.uuid == uuid));
  }

  // ── Financial math (mirrors backend calculatePromoFinancials) ──────────
  //
  // Cost approximation: LocalProduct doesn't carry purchase_price, so
  // the on-device preview uses `price * 0.7` as an "estimated cost"
  // with a clear label in the summary card. Backend authorises the
  // real margin when the promo is saved. Good enough for the
  // shopkeeper's red/green gut-check while editing.
  static const double _costFactor = 0.7;

  /// Snapshot BxPy actual — null en modo combo o si no hay producto.
  BuyXPayYFinancials? get _buyPayFinancials {
    if (_promoType != _PromoType.buyXPayY || _lines.isEmpty) return null;
    final p = _lines.first.product;
    return BuyXPayYFinancials.compute(
      unitPrice: p.price,
      unitCost: p.price * _costFactor,
      buyQty: _buyQty,
      payQty: _payQty,
    );
  }

  /// Costo estimado total. En modo BxPy el costo se calcula sobre las
  /// unidades que el cliente LLEVA (no las que paga), porque el
  /// tendero igual tiene que desembolsar esas X unidades del inventario.
  double get _estimatedCost {
    final bxp = _buyPayFinancials;
    if (bxp != null) return bxp.cost;
    return _lines.fold(
      0.0,
      (sum, l) => sum + (l.product.price * _costFactor) * l.quantity,
    );
  }

  double get _totalRegular {
    final bxp = _buyPayFinancials;
    if (bxp != null) return bxp.totalRegular;
    return _lines.fold(
      0.0,
      (sum, l) => sum + (l.product.price * l.quantity),
    );
  }

  double get _totalPromo {
    final bxp = _buyPayFinancials;
    if (bxp != null) return bxp.totalPromo;
    return _lines.fold(
      0.0,
      (sum, l) => sum + (l.promoPriceEach * l.quantity).toDouble(),
    );
  }

  double get _discountAmount => _totalRegular - _totalPromo;
  double get _discountPercent =>
      _totalRegular > 0 ? (_discountAmount / _totalRegular) * 100 : 0;
  double get _netProfit => _totalPromo - _estimatedCost;
  bool get _isProfitable => _netProfit >= 0;

  /// Validación del stepper de "Lleva/Paga": el cliente tiene que
  /// llevarse al menos 1 unidad más de las que paga (si no, no hay
  /// oferta), y paga ≥ 1.
  bool get _isBuyPayValid =>
      _promoType != _PromoType.buyXPayY ||
      (_lines.length == 1 && _payQty >= 1 && _buyQty > _payQty);

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

      // Serialización por tipo:
      //   * Combo → un item por línea con quantity/promoPriceEach.
      //   * BxPy  → un único item donde:
      //        quantity    = cuántas unidades se LLEVA el cliente.
      //        promo_price = precio unitario efectivo
      //                      (precio normal * payQty / buyQty).
      //     Matemáticamente equivalente al slogan "Lleva 3, paga 2" y
      //     encaja en el schema actual de PromotionItem sin cambios
      //     en el backend.
      final List<Map<String, dynamic>> items;
      final String promoType;
      final String description;
      if (_promoType == _PromoType.buyXPayY && _lines.isNotEmpty) {
        final p = _lines.first.product;
        final effectiveUnitPrice = (p.price * _payQty / _buyQty).round();
        items = [
          {
            'product_id': p.uuid,
            'quantity': _buyQty,
            'promo_price': effectiveUnitPrice,
          },
        ];
        promoType = 'buy_x_get_y';
        final userDesc = _customDiscountCtrl.text.trim();
        description = userDesc.isNotEmpty
            ? userDesc
            : 'Lleva $_buyQty, paga $_payQty';
      } else {
        items = _lines
            .map((l) => {
                  'product_id': l.product.uuid,
                  'quantity': l.quantity,
                  'promo_price': l.promoPriceEach,
                })
            .toList();
        promoType = 'combo';
        description = _customDiscountCtrl.text.trim();
      }

      final payload = <String, dynamic>{
        'id': promoId,
        'name': _nameCtrl.text.trim(),
        'promo_type': promoType,
        'description': description,
        'banner_image_url': _bannerUrl ?? '',
        'start_date': DateTime.now().toUtc().toIso8601String(),
        if (endDate != null) 'end_date': endDate.toUtc().toIso8601String(),
        if (_validity == _Validity.untilStockOut && _stockLimit != null)
          'stock_limit': _stockLimit,
        'items': items,
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
    final isBuyPay = _promoType == _PromoType.buyXPayY;

    return Column(
      children: [
        // Non-scrollable top section: type selector + name + search.
        // Extracted out of the ListView so the inventory scrolls under
        // a sticky search bar (less tiring on a 6" phone).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _promoTypeSelector(),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(fontSize: 18),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: isBuyPay
                      ? 'Nombre de la oferta'
                      : 'Nombre del combo',
                  hintText: isBuyPay
                      ? 'Ej: 3x2 en gaseosas'
                      : 'Ej: Combo Desayuno',
                  prefixIcon: const Icon(Icons.local_offer_rounded),
                ),
              ),
              const SizedBox(height: 12),
              if (_lines.isNotEmpty) _selectedChipsRow(),
              const SizedBox(height: 10),
              _searchField(),
            ],
          ),
        ),
        // Inventory list — the only scrollable piece of Step 1.
        Expanded(
          child: _searchResults.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No se encontraron productos.',
                      style: TextStyle(
                          fontSize: 15, color: AppTheme.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _resultTile(_searchResults[i]),
                ),
        ),
      ],
    );
  }

  /// SegmentedButton-style selector for combo vs. buy-X-pay-Y.
  /// Uses two side-by-side Cards because SegmentedButton renders very
  /// small on older Android density values — we want taps to be
  /// forgiving on phones held by 60+ users.
  Widget _promoTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: _typeCard(
            type: _PromoType.combo,
            icon: Icons.view_module_rounded,
            title: 'Combo Armado',
            subtitle: 'Varios productos juntos',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _typeCard(
            type: _PromoType.buyXPayY,
            icon: Icons.exposure_plus_2_rounded,
            title: 'Lleve X, Pague Y',
            subtitle: 'Un mismo producto',
          ),
        ),
      ],
    );
  }

  Widget _typeCard({
    required _PromoType type,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _promoType == type;
    return InkWell(
      key: Key('promo_type_${type.name}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _setPromoType(type),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.textSecondary),
                const SizedBox(width: 6),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppTheme.primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textPrimary,
                )),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 17),
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar producto en inventario…',
        prefixIcon: const Icon(Icons.search_rounded),
        // Clear button when there's text — faster than re-typing.
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : (_searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                    },
                  )),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  /// Compact row of chips showing the products currently in the
  /// promotion. Replaces the old bulky cards that dominated the
  /// screen and left no room for the inventory list.
  Widget _selectedChipsRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _lines.map((l) {
          return InputChip(
            key: Key('chip_${l.product.uuid}'),
            label: Text(
              l.product.name,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            avatar: const Icon(Icons.check_circle_rounded,
                color: AppTheme.primary, size: 18),
            backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
            side: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onDeleted: () => _removeLine(l.product.uuid),
            deleteIcon: const Icon(Icons.close_rounded, size: 18),
            deleteIconColor: AppTheme.textSecondary,
          );
        }).toList(),
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
      onTap: already ? null : () => _addLine(p),
    );
  }

  // ── Step 2: Financial Calculator ───────────────────────────────────────

  Widget _stepFinancialCalculator() {
    final isBuyPay = _promoType == _PromoType.buyXPayY;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          isBuyPay
              ? 'Define cuántas unidades se lleva y cuántas paga'
              : 'Ajusta cantidad y precio de cada producto',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (isBuyPay) _buyXPayYEditor() else ..._lines.map(_lineEditor),
        const SizedBox(height: 16),
        _summaryCard(),
      ],
    );
  }

  /// Editor visual del escenario "Lleve X, Pague Y". Dos steppers
  /// gigantes, un contador central grande (gerontodiseño), y la
  /// tarjeta de resumen financiero reacciona en tiempo real.
  Widget _buyXPayYEditor() {
    if (_lines.isEmpty) {
      // Safety net — validación del Paso 1 ya bloquea avanzar sin
      // producto, pero si alguien llega aquí mostramos un mensaje
      // claro en vez de crashear.
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
        ),
        child: const Text(
          'Vuelve al paso anterior y elige el producto de la oferta.',
          style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
        ),
      );
    }

    final p = _lines.first.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Producto escogido — fila compacta, no roba la pantalla.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shopping_bag_rounded,
                    color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Precio unitario: ${_cop(p.price)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _bigStepper(
          key: const Key('stepper_buy'),
          label: 'El cliente LLEVA',
          highlight: AppTheme.primary,
          value: _buyQty,
          min: 2,
          onChanged: (v) => setState(() {
            _buyQty = v;
            // Mantén la invariante buy > pay — si empujamos _buyQty
            // por debajo o igual a _payQty, bajamos _payQty 1 unidad.
            if (_buyQty <= _payQty) _payQty = _buyQty - 1;
            if (_payQty < 1) _payQty = 1;
          }),
        ),
        const SizedBox(height: 14),
        _bigStepper(
          key: const Key('stepper_pay'),
          label: 'El cliente PAGA',
          highlight: AppTheme.success,
          value: _payQty,
          min: 1,
          max: _buyQty - 1, // paga siempre < lleva (si no, no es oferta)
          onChanged: (v) => setState(() => _payQty = v),
        ),
        const SizedBox(height: 14),
        // Mini preview del slogan para validación visual.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.12),
                AppTheme.success.withValues(alpha: 0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'Lleva $_buyQty, paga $_payQty · Te regalas ${_buyQty - _payQty} '
            '${(_buyQty - _payQty) == 1 ? "unidad" : "unidades"}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// Stepper grande usado SOLO por el editor BxPy. Botones ±48px,
  /// número central en 34sp para legibilidad a distancia.
  Widget _bigStepper({
    required Key key,
    required String label,
    required Color highlight,
    required int value,
    required ValueChanged<int> onChanged,
    int min = 1,
    int? max,
  }) {
    final canDec = value > min;
    final canInc = max == null || value < max;
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: highlight,
                letterSpacing: 0.5,
              )),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circleButton(
                icon: Icons.remove_rounded,
                enabled: canDec,
                background: highlight,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onChanged(value - 1);
                },
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: highlight,
                  height: 1.0,
                ),
              ),
              _circleButton(
                icon: Icons.add_rounded,
                enabled: canInc,
                background: highlight,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onChanged(value + 1);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('unidades',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool enabled,
    required Color background,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled
          ? background
          : background.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(48),
      child: InkWell(
        borderRadius: BorderRadius.circular(48),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
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
      1 => _lines.isNotEmpty && _totalPromo > 0 && _isBuyPayValid,
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
