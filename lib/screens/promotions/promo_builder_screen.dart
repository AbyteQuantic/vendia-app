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
  /// Controller del input "¿En cuánto va a vender este combo?".
  /// Es el ÚNICO lugar donde el usuario escribe precio en modo combo:
  /// los precios por ítem se recalculan automáticamente en el payload.
  final _comboTotalCtrl = TextEditingController();
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
    _comboTotalCtrl.dispose();
    super.dispose();
  }

  /// Parsea el input del combo total ignorando puntos/comas/espacios
  /// — el tendero puede escribir "8.000", "8,000" o "8000".
  int? get _comboTotalValue {
    final raw = _comboTotalCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  /// Sugiere un precio combo inicial — 15 % de descuento sobre el total
  /// regular, redondeado a los $50 más cercanos (look-and-feel
  /// colombiano). Se usa para pre-poblar el campo al entrar al Paso 2.
  int get _suggestedComboTotal {
    if (_totalRegularBase <= 0) return 0;
    final v = ((_totalRegularBase * 0.85) / 50).ceil() * 50;
    return v.toInt();
  }

  /// Avanza al siguiente paso del wizard. Antes de entrar al Paso 2
  /// (combo), pre-poblamos el input "¿En cuánto va a vender este
  /// combo?" con el precio sugerido si el usuario aún no ha escrito
  /// nada. De este modo la tarjeta financiera muestra un número
  /// razonable de entrada en lugar de ceros.
  void _goNextStep() {
    if (_currentStep == 0 &&
        _promoType == _PromoType.combo &&
        _comboTotalCtrl.text.trim().isEmpty &&
        _suggestedComboTotal > 0) {
      _comboTotalCtrl.text = _suggestedComboTotal.toString();
    }
    setState(() => _currentStep++);
  }

  /// Suma price*qty de cada línea (la del combo "sin descuento") —
  /// base para calcular el total normal y distribuir el descuento.
  /// Nota: no usamos _totalRegular porque ese ya cubre también el
  /// escenario BxPy; aquí sólo nos interesa el combo clásico.
  double get _totalRegularBase => _lines.fold(
        0.0,
        (sum, l) => sum + (l.product.price * l.quantity),
      );

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

  /// Precio final que paga el cliente.
  ///   * BxPy: price * payQty (siempre derivado de los steppers).
  ///   * Combo: valor del input "¿En cuánto va a vender este combo?".
  ///     Si el usuario aún no ha escrito nada, cae al precio sugerido
  ///     (85 % del total regular). Las líneas individuales ya no
  ///     exponen precio — se distribuye proporcionalmente al guardar.
  double get _totalPromo {
    final bxp = _buyPayFinancials;
    if (bxp != null) return bxp.totalPromo;
    final typed = _comboTotalValue;
    if (typed != null) return typed.toDouble();
    return _suggestedComboTotal.toDouble();
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
      final auth = AuthService();
      final api = ApiService(auth);

      // V2 payload: empaquetamos la "propuesta de valor" completa para
      // que el backend se la pase al prompt imperativo de Gemini.
      //
      // DRY: el "Texto grande del banner" YA NO lo pide el Paso 4 —
      // se hereda del nombre del combo capturado en el Paso 1
      // (_nameCtrl), y el descuento se deriva automáticamente del
      // porcentaje calculado en el Paso 2. No le preguntamos al
      // tendero dos veces lo mismo.
      final discountPctRounded = _discountPercent.round();
      final tenantName = (await auth.getBusinessName())?.trim();
      final comboTitle = _nameCtrl.text.trim();
      final normalPriceStr = _cop(_totalRegular);
      final promoPriceStr = _cop(_totalPromo);
      final savingsAmount =
          (_totalRegular - _totalPromo).clamp(0, double.infinity);
      final savingsStr =
          savingsAmount > 0 ? 'Ahorras ${_cop(savingsAmount)}' : '';
      final discountStr =
          discountPctRounded > 0 ? '$discountPctRounded% OFF' : '';

      final res = await api.generatePromoBanner(
        promoName: comboTitle,
        productNames: _lines.map((l) => l.product.name).toList(),
        discountText: discountStr, // ← deriva del % calculado, no de un input manual
        tone: _tone,
        tenantName: tenantName,
        comboTitle: comboTitle,
        normalPriceStr: normalPriceStr,
        promoPriceStr: promoPriceStr,
        discountStr: discountStr,
        savingsStr: savingsStr,
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
        // La descripción se deriva automáticamente de las cantidades
        // del Paso 2 — ya no hay un input libre que mantener en sync.
        description = 'Lleva $_buyQty, paga $_payQty';
      } else {
        // Combo "Tendero-Speak": el usuario sólo escribió el
        // TOTAL del combo en _comboTotalCtrl. Distribuimos ese total
        // proporcionalmente al peso (price * quantity) de cada línea.
        // Así el backend sigue recibiendo promo_price por ítem y no
        // hay que tocar schemas; el último ítem absorbe el redondeo
        // para que la suma cuadre exacto con lo que escribió el
        // usuario.
        final totalCombo = _comboTotalValue ?? _suggestedComboTotal;
        final distributed = distributeComboTotal(
          lines: _lines
              .map((l) => ComboLineInput(
                    productId: l.product.uuid,
                    unitPrice: l.product.price,
                    quantity: l.quantity,
                  ))
              .toList(),
          totalComboPrice: totalCombo,
        );
        items = distributed
            .map((d) => {
                  'product_id': d.productId,
                  'quantity': d.quantity,
                  'promo_price': d.promoPriceEach,
                })
            .toList();
        // Sincronizamos también las líneas en memoria para que la
        // Step 2 refleje el precio real que se va a guardar (por si el
        // usuario vuelve a editar sin salir de la pantalla).
        for (var i = 0; i < _lines.length; i++) {
          _lines[i].promoPriceEach = distributed[i].promoPriceEach;
        }
        promoType = 'combo';
        // Description se hereda silenciosamente del nombre del combo
        // (Paso 1). No queremos pedirle al tendero un "texto del
        // banner" redundante en el Paso 4.
        description = _nameCtrl.text.trim();
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
              : 'Ajuste la cantidad de cada producto',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (isBuyPay)
          _buyXPayYEditor()
        else ...[
          ..._lines.map(_lineEditor),
          const SizedBox(height: 18),
          _comboTotalField(),
        ],
        const SizedBox(height: 16),
        _summaryCard(),
      ],
    );
  }

  /// Input gigante "¿En cuánto va a vender este combo?" — el ÚNICO
  /// campo de precio en modo combo. La distribución proporcional por
  /// ítem ocurre al guardar (ver [distributeComboTotal]).
  Widget _comboTotalField() {
    return Container(
      key: const Key('combo_total_field'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_offer_rounded,
                  color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '¿En cuánto va a vender este combo?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 30),
            child: Text(
              'Usted solo pone el precio total. Nosotros hacemos las cuentas.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comboTotalCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
              hintText: _suggestedComboTotal > 0
                  ? _suggestedComboTotal.toString()
                  : '0',
              hintStyle: TextStyle(
                fontSize: 32,
                color: Colors.grey.shade400,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 2),
              ),
            ),
          ),
        ],
      ),
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

  /// Tarjeta individual del combo. SÓLO muestra nombre, precio normal
  /// y ajustador de cantidad grande. El precio por unidad ya no se
  /// edita aquí — se distribuye proporcionalmente a partir del input
  /// global "¿En cuánto va a vender este combo?".
  Widget _lineEditor(_PromoLine l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.product.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'Precio normal: ${_cop(l.product.price)}',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _bigSquareStepper(
            value: l.quantity,
            onChanged: (v) => setState(() => l.quantity = v),
          ),
        ],
      ),
    );
  }

  /// Stepper cuadrado grande (gerontodiseño): botones de 56×56, número
  /// central en `HeadlineMedium`, feedback háptico. Mismo look & feel
  /// en combo y en BxPy.
  Widget _bigSquareStepper({
    required int value,
    required ValueChanged<int> onChanged,
    int min = 1,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _squareStepperBtn(
          icon: Icons.remove_rounded,
          onTap: () {
            if (value > min) {
              HapticFeedback.lightImpact();
              onChanged(value - 1);
            }
          },
          enabled: value > min,
        ),
        SizedBox(
          width: 56,
          child: Center(
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
        _squareStepperBtn(
          icon: Icons.add_rounded,
          onTap: () {
            HapticFeedback.lightImpact();
            onChanged(value + 1);
          },
          enabled: true,
        ),
      ],
    );
  }

  Widget _squareStepperBtn({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Material(
      color: enabled
          ? AppTheme.primary
          : AppTheme.primary.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  /// Tarjeta financiera estilo "recibo de tienda" — gerontodiseño:
  /// frases coloquiales, 4 líneas semánticas, sin porcentajes.
  ///
  ///   Línea 1 (gris):   Precio normal por separado
  ///   Línea 2 (gris):   Costo de su mercancía
  ///   Línea 3 (naranja):Usted le rebaja al cliente
  ///   Línea 4 (verde):  Plata libre para su bolsillo  (XL bold)
  Widget _summaryCard() {
    final profitColor =
        _isProfitable ? AppTheme.success : AppTheme.error;
    return Container(
      key: const Key('summary_receipt_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: profitColor.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: profitColor.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: AppTheme.textSecondary, size: 20),
              SizedBox(width: 8),
              Text(
                'La cuenta rápida',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _receiptRow(
            label: 'Precio normal por separado:',
            value: _cop(_totalRegular),
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 6),
          _receiptRow(
            label: 'Costo de su mercancía:',
            value: _cop(_estimatedCost),
            color: AppTheme.textSecondary,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: DashedDivider(),
          ),
          _receiptRow(
            label: 'Usted le rebaja al cliente:',
            value: _cop(_discountAmount),
            color: AppTheme.warning,
            bold: true,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: profitColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: profitColor.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isProfitable
                      ? 'Plata libre para su bolsillo:'
                      : 'Está perdiendo plata:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: profitColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _cop(_netProfit),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: profitColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          if (!_isProfitable) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '⚠️ Con este precio usted pierde plata. Suba el precio del combo o quite algún producto.',
                style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.error,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Fila tipo recibo: etiqueta a la izquierda, valor a la derecha
  /// alineado, mismo color semántico en ambos. Sin porcentajes.
  Widget _receiptRow({
    required String label,
    required String value,
    required Color color,
    bool bold = false,
  }) {
    final weight = bold ? FontWeight.w800 : FontWeight.w500;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 16, color: color, fontWeight: weight),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 19 : 17,
            color: color,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
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
    // Layout redesign (2026-04): el Paso 4 tenía 3 problemas graves:
    //  1. Un TextField de "Texto grande del banner" DUPLICABA el nombre
    //     del combo ya ingresado en el Paso 1. El tendero tecleaba lo
    //     mismo dos veces. Eliminado → el título se hereda de _nameCtrl.
    //  2. Los chips de tono ocupaban hasta 2 renglones en celulares de
    //     360 dp y empujaban al CTA principal fuera de la vista.
    //  3. El botón morado "Generar con IA" quedaba debajo del fold.
    //
    // Nueva jerarquía (de arriba hacia abajo):
    //    [carrusel horizontal de tonos — 56 dp]
    //    [preview cuadrado del banner — AspectRatio 1:1]
    //    [CTA principal: "✨ Generar con IA" — 56 dp morado]
    //    [CTA secundario: "Subir foto desde galería" — 52 dp outlined]
    // Así el usuario abre el paso y ve de un golpe: qué estilo elegir,
    // cómo va quedando, y el botón mágico.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text('Estudio creativo',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Elige un estilo y genera un banner publicitario con IA.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),

        // 1. Carrusel horizontal de estilos. Altura fija (56 dp) para
        //    que NUNCA empuje al CTA, y scrolleable para soportar más
        //    tonos sin rediseñar.
        _toneCarousel(),
        const SizedBox(height: 14),

        // 2. Main focus: el banner preview cuadrado.
        _bannerPreview(),
        const SizedBox(height: 14),

        // 3. CTA principal inmediatamente pegado al preview.
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

        // 4. CTA secundario. Siempre disponible como fallback si la
        //    IA no entrega un resultado a gusto del tendero.
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

  /// Carrusel horizontal de chips de tono. Altura fija de 56 dp para
  /// que sea predecible en el layout y jamás empuje al CTA fuera de
  /// la vista. Scrollea en horizontal (estilo barra de filtros de
  /// Instagram) para soportar más tonos a futuro sin rediseñar.
  Widget _toneCarousel() {
    const tones = <(String, String)>[
      ('vibrante', '🎨 Vibrante'),
      ('elegante', '✨ Elegante'),
      ('urgente', '🔥 Urgente'),
    ];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: tones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _toneChip(tones[i].$1, tones[i].$2),
      ),
    );
  }

  Widget _toneChip(String value, String label) {
    final selected = _tone == value;
    // Compacto: padding reducido para que el carrusel se vea como una
    // barra de filtros de Instagram, no como botones enormes.
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _tone = value);
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      labelStyle: TextStyle(
        color: selected ? AppTheme.primary : AppTheme.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        : _goNextStep),
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

/// Entrada para [distributeComboTotal]: un producto del combo en su
/// forma mínima (id + precio unitario normal + cantidad).
///
/// `unitPrice` se acepta como `num` para aceptar tanto `int` como
/// `double` (LocalProduct.price es double en la app, los tests usan
/// ints).
class ComboLineInput {
  final String productId;
  final num unitPrice;
  final int quantity;
  const ComboLineInput({
    required this.productId,
    required this.unitPrice,
    required this.quantity,
  });
}

/// Resultado: cuánto pagará el cliente por cada UNIDAD de ese
/// producto dentro del combo.
class ComboLineDistribution {
  final String productId;
  final int quantity;
  final int promoPriceEach;
  const ComboLineDistribution({
    required this.productId,
    required this.quantity,
    required this.promoPriceEach,
  });
}

/// Distribuye el precio TOTAL del combo proporcionalmente entre sus
/// ítems, respetando el peso original (price * quantity) de cada
/// línea. Función pura — testeable sin widget.
///
/// Contrato:
///   * Si la suma de precios regulares es 0 (edge case con productos
///     de precio 0), se reparte uniformemente por unidad.
///   * El último ítem absorbe el residuo de redondeo para garantizar
///     `Σ promoPriceEach*quantity == totalComboPrice`.
///   * `promoPriceEach` nunca es negativo (piso en 0).
List<ComboLineDistribution> distributeComboTotal({
  required List<ComboLineInput> lines,
  required int totalComboPrice,
}) {
  if (lines.isEmpty) return const [];
  final safeTotal = totalComboPrice < 0 ? 0 : totalComboPrice;

  final totalRegular = lines.fold<double>(
    0,
    (sum, l) => sum + l.unitPrice.toDouble() * l.quantity,
  );

  final result = <ComboLineDistribution>[];
  int allocated = 0;

  if (totalRegular <= 0) {
    final totalUnits = lines.fold<int>(0, (s, l) => s + l.quantity);
    if (totalUnits == 0) return const [];
    final perUnit = (safeTotal / totalUnits).floor();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final isLast = i == lines.length - 1;
      final lineTotal =
          isLast ? safeTotal - allocated : perUnit * l.quantity;
      final perEach = l.quantity == 0 ? 0 : (lineTotal / l.quantity).round();
      allocated += perEach * l.quantity;
      result.add(ComboLineDistribution(
        productId: l.productId,
        quantity: l.quantity,
        promoPriceEach: perEach < 0 ? 0 : perEach,
      ));
    }
    return result;
  }

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final weight = l.unitPrice.toDouble() * l.quantity;
    final isLast = i == lines.length - 1;
    final lineTotal = isLast
        ? safeTotal - allocated
        : ((safeTotal * weight) / totalRegular).round();
    final perEach =
        l.quantity == 0 ? 0 : (lineTotal / l.quantity).round();
    final lineActual = perEach * l.quantity;
    allocated += lineActual;
    result.add(ComboLineDistribution(
      productId: l.productId,
      quantity: l.quantity,
      promoPriceEach: perEach < 0 ? 0 : perEach,
    ));
  }
  return result;
}

/// Separador punteado horizontal estilo recibo de caja — reproduce la
/// sensación de "tirilla" para reforzar la metáfora financiera.
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color = const Color(0xFFBDBDBD)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 4.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(count, (_) {
            return SizedBox(
              width: dash,
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
        );
      },
    );
  }
}
