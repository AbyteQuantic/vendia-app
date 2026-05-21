// Spec: specs/028-copy-fiar-credito-configurable/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
// Spec: specs/030-administracion-clientes-no-tienda/spec.md
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_payment_method.dart';
import '../../models/cart_item.dart';
import '../customers/customer_selector_sheet.dart';
import '../../services/active_fiado_service.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/bank_notification_service.dart';
import '../../services/role_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_labels.dart';
import '../../widgets/owner_pin_dialog.dart';
import '../../widgets/receipt_image_picker.dart';
import 'cart_controller.dart';

class CheckoutResult {
  final bool confirmed;
  final String paymentMethod;
  /// When the cashier chose "Agregar a cuenta existente", this is the id
  /// of the fiado we appended to. POS forwards it when syncing the sale
  /// so the backend can link the sale to the account and the public
  /// statement can show the itemized detail.
  final String? creditAccountId;
  /// True when the fiado link is still awaiting customer acceptance — the
  /// cashier hit "Seguir vendiendo" before polling saw the accept. The
  /// success screen uses this to show "Venta guardada · Esperando firma"
  /// instead of the full-green "¡Venta registrada!" so nothing looks
  /// like it was silently auto-accepted.
  final bool fiadoPending;
  /// Customer name captured on the handshake form, propagated so the
  /// POS slot bubble can render "Fiado: <name>" while the credit stays
  /// pending. Null on non-credit flows.
  final String? customerName;
  /// Customer phone captured on the handshake form. Mirrors
  /// [customerName] — the POS slot keeps it so the cashier can
  /// re-resend the WhatsApp link from the cart bubble's overflow menu
  /// without re-typing.
  final String? customerPhone;
  /// For "Transferencia" (Plan B zero-fee QR) flows: the raw QR payload
  /// that was shown to the customer. Persisted on the Sale row so the
  /// tenant keeps an audit trail and a future webhook reconciler can
  /// match Nequi/Daviplata SMS notifications to the sale.
  final String? dynamicQrPayload;
  /// Public URL of the receipt photo the cashier attached to the
  /// digital payment (Mandatory Image Receipts epic). Null for cash
  /// sales and for fiado handshakes — the latter handle their own
  /// audit via the public statement.
  final String? receiptImageUrl;
  const CheckoutResult({
    required this.confirmed,
    required this.paymentMethod,
    this.creditAccountId,
    this.fiadoPending = false,
    this.customerName,
    this.customerPhone,
    this.dynamicQrPayload,
    this.receiptImageUrl,
  });
}

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> items;
  final String formattedTotal;
  final double total;

  /// When true the screen auto-launches the Fiado handshake sheet on
  /// first frame. Used by the POS "slot fiado" entry point so the
  /// cashier never lands on a half-open credit account that bypasses
  /// the backend handshake.
  final bool forceFiadoFlow;

  /// Optional prefill of the customer name + phone for the Fiado
  /// handshake. Lets the slot-fiado entry point keep the data the
  /// cashier already typed instead of asking again.
  final String? prefillCustomerName;
  final String? prefillCustomerPhone;

  const CheckoutScreen({
    super.key,
    required this.items,
    required this.formattedTotal,
    required this.total,
    this.forceFiadoFlow = false,
    this.prefillCustomerName,
    this.prefillCustomerPhone,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // Sentinel keys for non-tenant chips. The fiar key is a UI-only
  // construct because "fiar" is not a payment method per se — it's a
  // credit booking that takes a totally different code path.
  /// Sentinel for the cash chip selection. The chip is the SAME
  /// regardless of whether we render the tenant's real cash row or a
  /// synthetic Efectivo fallback — Cash-First policy ensures it's
  /// always present and always uses this key.
  static const String _kFallbackCash = '__cash_anchor__';
  static const String _kFiar = '__fiar__';

  /// The tenant-configured method the cashier picked, when any. Null
  /// while the fallback cash chip or the Fiar chip is selected.
  LocalPaymentMethod? _selectedMethod;

  /// Stable key for the chip currently selected. For tenant methods
  /// it's the method's uuid; for the fallback / fiar chips it's the
  /// matching sentinel. Driving the selection state from a key (and
  /// not the LocalPaymentMethod reference) keeps the chosen chip
  /// stable across stream rebuilds even if the underlying ISAR
  /// instance is replaced.
  String _selectedMethodKey = _kFallbackCash;

  double _amountTendered = 0;
  final _manualCtrl = TextEditingController();

  // Mirrors the global "Configuración de Fiados" switch on the admin
  // hub. When the tendero has credit disabled we hide the "Fiar"
  // payment chip entirely so the cashier can't register a fiado that
  // shouldn't exist. Default to `true` so a network failure doesn't
  // silently remove the chip for a merchant who expects it.
  bool _fiadoEnabled = true;

  // F029 — capacidad enable_price_tiers + nombres custom de los tiers.
  // Default OFF (fail-closed): tenants pre-F029 ven la pantalla
  // exactamente como antes (AC-01/AC-07). Cuando es ON renderizamos
  // un selector "Tipo de precio" arriba del resumen.
  bool _enablePriceTiers = false;
  String _tier1Name = 'Depósito contado';
  String _tier2Name = 'Depósito crédito';
  String _tier3Name = 'Cliente final';

  // F029: total efectivo recalculado en cada build, usado por los
  // getters `_change` / `_isExact` que no tienen acceso al BuildContext.
  // Cuando enable_price_tiers está OFF coincide siempre con widget.total.
  double _currentTotal = 0;

  // F030 — capacidad enable_customer_management. Default OFF
  // (fail-closed): tenants sin la capacidad ven la pantalla idéntica a
  // hoy (AC-07). Cuando es ON renderizamos un tile "Cliente" al inicio.
  bool _enableCustomerManagement = false;

  static const _denominations = [2000, 5000, 10000, 20000, 50000, 100000];

  // F029: usamos `_currentTotal` (refrescado en cada build con el tier
  // activo). Para tenants sin la capacidad o sin CartController coincide
  // con widget.total → comportamiento legacy intacto.
  double get _change => _amountTendered - _currentTotal;
  bool get _isExact => (_amountTendered - _currentTotal).abs() < 1;

  /// True when the selected chip should behave as plain cash —
  /// either the synthetic fallback chip or a tenant-configured
  /// method whose provider is `cash`. The cash-change panel only
  /// renders when this is true.
  bool get _isCash =>
      _selectedMethodKey == _kFallbackCash ||
      (_selectedMethod?.provider == 'cash');

  /// Supabase URL of the receipt photo the cashier attached. Empty
  /// for cash sales (the picker only renders for digital methods).
  /// Drives the "Confirmar Pago" gate alongside the cash-tendered
  /// check. Mandatory Image Receipts epic — PO mandate.
  String? _receiptUrl;

  /// Mandatory image gating. The button is enabled only when:
  ///   * cash with enough tendered, OR
  ///   * non-cash with `_receiptUrl != null` (image successfully
  ///     uploaded to Supabase), OR
  ///   * fiar WITH a completed handshake — i.e.
  ///     `ActiveFiadoService.hasActive` is true (H11 fix).
  ///
  /// CRITICAL: a bank notification flashing in the background does
  /// NOT flip this — see [BankNotificationService] for the rationale.
  /// Prior to the H11 fix the fiar branch returned `true`
  /// unconditionally; tapping "Confirmar" then opened the
  /// handshake sheet on the fly — but the button label and look
  /// implied the sale was confirmable. Now the button stays
  /// disabled until the handshake produces an accepted account
  /// (see [_handleFiarChipSelected] for the sheet dispatch).
  // F029: el cálculo de "puede confirmar?" se hace contra el total
  // *efectivo* (que cambia si el cajero seleccionó un tier diferente al
  // retail). Para retrocompat, el llamador anterior pasa
  // `widget.total` cuando la capacidad está OFF.
  bool _canConfirmWith({
    required bool hasActiveFiado,
    double? effectiveTotal,
  }) {
    if (_selectedMethodKey == _kFiar) return hasActiveFiado;
    final total = effectiveTotal ?? widget.total;
    if (_isCash) return _amountTendered >= total;
    return _receiptUrl != null && _receiptUrl!.isNotEmpty;
  }

  /// Always show all common denominations so the user can combine
  List<int> get _smartBills => _denominations;

  void _setTendered(double value) {
    setState(() {
      _amountTendered = value;
      _manualCtrl.text = value.round().toString();
    });
    HapticFeedback.lightImpact();
  }

  @override
  void initState() {
    super.initState();
    _amountTendered = widget.total; // default to exact
    _currentTotal = widget.total; // F029: refrescado en build()
    _loadFiadoFlag();
    _loadPriceTierConfig();
    _loadCustomerManagementFlag();
    if (widget.forceFiadoFlow) {
      // Defer until the first frame so the Scaffold + AppBar are mounted
      // and the handshake bottom sheet can attach to a real BuildContext.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showFiadoChoiceSheet();
      });
    }
    // Bank notification listener — purely informative. SnackBar fires
    // when the bank app's notification is captured by the native
    // listener; nothing else here ever depends on it.
    BankNotificationService.instance.addListener(_onBankNotif);
  }

  @override
  void dispose() {
    BankNotificationService.instance.removeListener(_onBankNotif);
    _manualCtrl.dispose();
    super.dispose();
  }

  void _onBankNotif() {
    if (!mounted) return;
    final svc = BankNotificationService.instance;
    final bank = svc.lastDetectedBank;
    if (bank == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        content: Text('✅ Notificación bancaria detectada · $bank',
            style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Pulls the live tenant flag that gates the "Fiar" payment chip.
  /// Non-blocking — the screen still renders with the `true` default
  /// while the network round-trip completes; if the tendero has
  /// disabled fiados the chip disappears as soon as the GET returns.
  /// Failures (offline, 401) keep the default so a transient error
  /// can't silently hide a legitimate payment method.
  Future<void> _loadFiadoFlag() async {
    try {
      final api = ApiService(AuthService());
      final config = await api.fetchStoreConfig();
      if (!mounted) return;
      setState(() {
        _fiadoEnabled = config['enable_fiados'] as bool? ?? true;
        // If the tendero turned fiados off WHILE the cashier was on
        // the checkout screen with "Fiar" selected, flip the selection
        // back to the cash fallback so we don't end up posting a fiado
        // the tenant no longer allows.
        if (!_fiadoEnabled && _selectedMethodKey == _kFiar) {
          _selectedMethod = null;
          _selectedMethodKey = _kFallbackCash;
        }
      });
    } catch (_) {
      // Keep the default (true). The admin hub flag is the source of
      // truth; an offline cashier shouldn't lose the "Fiar" option.
    }
  }

  // F029 — leemos enable_price_tiers + los nombres custom desde feature
  // flags persistidos por AuthService (offline-safe) y desde el
  // /store/profile para refrescar los nombres si el dueño los acaba de
  // editar. Fail-closed: cualquier error deja _enablePriceTiers=false.
  Future<void> _loadPriceTierConfig() async {
    try {
      final flags = await AuthService().getFeatureFlags();
      if (!mounted) return;
      if (!flags.enablePriceTiers) {
        setState(() => _enablePriceTiers = false);
        return;
      }
      String t1 = _tier1Name;
      String t2 = _tier2Name;
      String t3 = _tier3Name;
      try {
        final profile =
            await ApiService(AuthService()).fetchBusinessProfile();
        final raw1 = (profile['price_tier_1_name'] as String?)?.trim();
        final raw2 = (profile['price_tier_2_name'] as String?)?.trim();
        final raw3 = (profile['price_tier_3_name'] as String?)?.trim();
        if (raw1 != null && raw1.isNotEmpty) t1 = raw1;
        if (raw2 != null && raw2.isNotEmpty) t2 = raw2;
        if (raw3 != null && raw3.isNotEmpty) t3 = raw3;
      } catch (_) {
        // Mantener defaults si el GET revienta.
      }
      if (!mounted) return;
      setState(() {
        _enablePriceTiers = true;
        _tier1Name = t1;
        _tier2Name = t2;
        _tier3Name = t3;
      });
    } catch (_) {
      if (mounted) setState(() => _enablePriceTiers = false);
    }
  }

  // F029 — el cart controller es la SSOT del tier elegido + cálculo de
  // totales. La lectura efectiva ocurre dentro de build() via
  // context.watch<CartController>(); no exponemos un helper aparte para
  // mantener el grafo de dependencias mínimo.

  // F030 — leemos enable_customer_management desde los feature flags
  // persistidos por AuthService (offline-safe). Fail-closed: cualquier
  // error deja _enableCustomerManagement=false → cero UI nueva (AC-07).
  Future<void> _loadCustomerManagementFlag() async {
    try {
      final flags = await AuthService().getFeatureFlags();
      if (!mounted) return;
      setState(() =>
          _enableCustomerManagement = flags.enableCustomerManagement);
    } catch (_) {
      if (mounted) setState(() => _enableCustomerManagement = false);
    }
  }

  String _formatCOP(int amount) {
    if (amount == 0) return '\$0';
    final negative = amount < 0;
    final abs = amount.abs().toString();
    final buffer = StringBuffer(negative ? '-\$' : '\$');
    final start = abs.length % 3;
    if (start > 0) buffer.write(abs.substring(0, start));
    for (int i = start; i < abs.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(abs.substring(i, i + 3));
    }
    return buffer.toString();
  }

  IconData _iconForProvider(String? provider, String name) {
    final p = (provider ?? '').toLowerCase();
    final n = name.toLowerCase();
    if (p == 'nequi' || n.contains('nequi')) return Icons.phone_android_rounded;
    if (p == 'daviplata' || n.contains('daviplata')) return Icons.phone_android_rounded;
    if (p == 'qr' || n.contains('qr')) return Icons.qr_code_rounded;
    if (n.contains('bancolombia') || n.contains('banco')) return Icons.account_balance_rounded;
    return Icons.account_balance_wallet_rounded;
  }

  Color? _colorForProvider(String? provider, String name) {
    final p = (provider ?? '').toLowerCase();
    final n = name.toLowerCase();
    if (p == 'nequi' || n.contains('nequi')) return const Color(0xFF6D28D9);
    if (p == 'daviplata' || n.contains('daviplata')) return const Color(0xFFDC2626);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Subscribed: when the cuaderno polling marks the fiado
    // accepted, this rebuild flips `_canConfirmWith` and enables
    // the Confirmar button.
    final hasActiveFiado = context.watch<ActiveFiadoService>().hasActive;
    // F029: nos suscribimos al CartController cuando existe para que
    // un cambio de tier (vía setPriceTier) recalcule total + subtotales
    // al instante (AC-05). Si el screen se monta sin Provider (tests)
    // usamos los valores constructor-time.
    CartController? cartCtrl;
    try {
      cartCtrl = context.watch<CartController>();
    } catch (_) {
      cartCtrl = null;
    }
    final effectiveTotal =
        (_enablePriceTiers && cartCtrl != null) ? cartCtrl.activeTotal : widget.total;
    final effectiveFormatted = (_enablePriceTiers && cartCtrl != null)
        ? cartCtrl.formattedTotal
        : widget.formattedTotal;
    // Mantener el campo _currentTotal en sync para los getters
    // _change/_isExact que no tienen contexto. Hacemos también un
    // re-default del monto recibido (exacto) cuando el cajero NO ha
    // movido el slider manualmente — sin esta línea cambiar el tier
    // dejaría las "vueltas" como una resta contra el total previo.
    if (_currentTotal != effectiveTotal) {
      _currentTotal = effectiveTotal;
      // Si el cajero estaba en "Exacto" (vale por igualdad floor a 1
      // peso) ajustamos también lo que tendrá la caja registradora.
      if ((_amountTendered - widget.total).abs() < 1 ||
          _amountTendered == 0) {
        _amountTendered = effectiveTotal;
        // No usamos setState — ya estamos en build; mutamos el campo y
        // el siguiente frame re-pintará via watch del CartController.
      }
    }
    final canConfirm = _canConfirmWith(
      hasActiveFiado: hasActiveFiado,
      effectiveTotal: effectiveTotal,
    );
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
        title: const Text('Confirmar Venta',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary)),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  // ── F030: tile "Cliente" — solo cuando
                  //    enable_customer_management está ON. Aparece al
                  //    inicio (antes del selector de tier y del resumen)
                  //    para que el cajero asocie el cliente primero.
                  if (_enableCustomerManagement && cartCtrl != null) ...[
                    _buildCustomerTile(cartCtrl),
                    const SizedBox(height: 16),
                  ],

                  // ── F029: selector "Tipo de precio" — solo cuando
                  //    enable_price_tiers está ON. Aparece ANTES del
                  //    resumen para que el cajero elija primero.
                  if (_enablePriceTiers && cartCtrl != null) ...[
                    _buildPriceTierSelector(cartCtrl),
                    const SizedBox(height: 20),
                  ],

                  // ── Item summary ──────────────────────────────────
                  const Text('Resumen',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < widget.items.length; i++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: _buildSummaryRow(
                              widget.items[i],
                              cartCtrl: cartCtrl,
                            ),
                          ),
                          if (i < widget.items.length - 1)
                            const Divider(height: 1, indent: 20, endIndent: 20),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Total ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL',
                            style: TextStyle(fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                        // F029: usar effectiveFormatted para que el
                        // TOTAL grande refleje el tier seleccionado.
                        Text(
                          key: const Key('checkout_total_value'),
                          effectiveFormatted,
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Payment methods ───────────────────────────────
                  const Text('Método de pago',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  StreamBuilder<List<LocalPaymentMethod>>(
                    stream: DatabaseService.instance.watchActivePaymentMethods(),
                    builder: (ctx, snap) {
                      final tenantMethods =
                          snap.data ?? const <LocalPaymentMethod>[];

                      // Cash-First INNEGOCIABLE: a checkout NEVER ships without
                      // Efectivo. Three rules collapse into one rendered chip:
                      //   1. If the tenant has an active cash row, render IT (so the
                      //      owner's display label wins).
                      //   2. If the tenant has NO cash row in the active set, render
                      //      a synthetic Efectivo chip — same key, same dispatcher
                      //      behaviour.
                      //   3. Either way, the chip is the FIRST child of the Wrap and
                      //      shares the _kFallbackCash sentinel for selection state.
                      LocalPaymentMethod? realCash;
                      for (final m in tenantMethods) {
                        if (!m.isActive) continue;
                        if (m.name.trim().isEmpty) continue;
                        final isCash = m.provider == 'cash' ||
                            m.name.trim().toLowerCase() == 'efectivo';
                        if (isCash) {
                          realCash = m;
                          break;
                        }
                      }

                      // Non-cash active methods render after the cash anchor. Strip
                      // any blank-name rows and any cash row (we already handled it).
                      final nonCashActive = tenantMethods.where((m) {
                        if (!m.isActive) return false;
                        if (m.name.trim().isEmpty) return false;
                        if (m.provider == 'cash') return false;
                        if (m.name.trim().toLowerCase() == 'efectivo') return false;
                        return true;
                      }).toList();

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          // Cash anchor — ALWAYS first, ALWAYS selectable.
                          // Uses _kFallbackCash as the selection key whether the row
                          // is real or synthetic, so the dispatcher in _confirmSale
                          // does not need to know which case it is.
                          _PaymentChip(
                            key: ValueKey(realCash != null
                                ? 'checkout_pm_cash_${realCash.uuid}'
                                : 'checkout_pm_fallback_cash'),
                            icon: Icons.payments_rounded,
                            label: realCash?.name ?? 'Efectivo',
                            selected: _selectedMethodKey == _kFallbackCash,
                            onTap: () => setState(() {
                              // Store the real row when present so other parts of the
                              // sale path can read accountDetails (e.g. cash drawer
                              // notes); fall back to null for synthetic.
                              _selectedMethod = realCash;
                              _selectedMethodKey = _kFallbackCash;
                            }),
                          ),
                          // Tenant non-cash active methods.
                          ...nonCashActive.map((m) {
                            final key = m.uuid;
                            return _PaymentChip(
                              key: ValueKey('checkout_pm_${m.uuid}'),
                              icon: _iconForProvider(m.provider, m.name),
                              label: m.name,
                              selected: _selectedMethodKey == key,
                              onTap: () => setState(() {
                                _selectedMethod = m;
                                _selectedMethodKey = key;
                              }),
                              color: _colorForProvider(m.provider, m.name),
                            );
                          }),
                          // Fiar — gated by feature flag, completely separate from
                          // tenant payment methods. Order: cash anchor → tenant
                          // non-cash → fiar.
                          if (_fiadoEnabled)
                            _PaymentChip(
                              key: const Key('checkout_payment_chip_fiar'),
                              icon: Icons.menu_book_rounded,
                              label: CreditLabels.of(context).checkoutChipLabel,
                              selected: _selectedMethodKey == _kFiar,
                              onTap: () {
                                setState(() {
                                  _selectedMethod = null;
                                  _selectedMethodKey = _kFiar;
                                });
                                // H11: tapping the Fiar chip without an
                                // already-active fiado dispatches the
                                // handshake sheet on the spot. Before this
                                // fix the Confirmar button stayed enabled
                                // and pretended the sale was confirmable;
                                // now the cashier is funnelled straight
                                // into the handshake and the primary
                                // button only enables when the customer
                                // accepts.
                                final active =
                                    context.read<ActiveFiadoService>();
                                if (!active.hasActive) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    _showFiadoChoiceSheet();
                                  });
                                }
                              },
                              color: const Color(0xFFF59E0B),
                            ),
                        ],
                      );
                    },
                  ),

                  // ── Cash change panel ─────────────────────────────
                  if (_isCash) ...[
                    const SizedBox(height: 24),
                    const Text('Paga con...',
                        style: TextStyle(fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),

                    // Quick bill buttons
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        // "Exacto" button. F029: usa el effectiveTotal
                        // (que cambia con el tier seleccionado) en vez
                        // del widget.total constructor-time.
                        _BillChip(
                          label: 'Exacto',
                          selected: _isExact,
                          onTap: () => _setTendered(effectiveTotal),
                        ),
                        // Denomination buttons
                        for (final bill in _smartBills)
                          _BillChip(
                            label: _formatCOP(bill),
                            selected: (_amountTendered - bill).abs() < 1,
                            onTap: () => _setTendered(bill.toDouble()),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Manual input
                    TextField(
                      controller: _manualCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 22,
                          fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Otro valor...',
                        hintStyle: TextStyle(fontSize: 20,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.normal),
                        prefixIcon: const Icon(Icons.edit_rounded,
                            color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.surfaceGrey,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v) ?? 0;
                        setState(() => _amountTendered = parsed);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Change result card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _change >= 0
                            ? AppTheme.success.withValues(alpha: 0.08)
                            : AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _change >= 0
                              ? AppTheme.success.withValues(alpha: 0.3)
                              : AppTheme.error.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _change >= 0
                                ? 'Vueltas a entregar:'
                                : 'Falta dinero:',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: _change >= 0
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatCOP(_change.abs().round()),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: _change >= 0
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // ── Comprobante (epic Mandatory Image Receipts) ─
                  // Only renders for digital payments — cash sales
                  // bypass the gate entirely. Fiar uses its own
                  // handshake flow so no receipt is asked here.
                  if (!_isCash && _selectedMethodKey != _kFiar) ...[
                    const Text('Comprobante de pago',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    ReceiptImagePicker(
                      onImageReady: (url) =>
                          setState(() => _receiptUrl = url),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),

            // ── Confirm button ──────────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                  24, 12, 24, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: canConfirm ? _confirmSale : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    disabledBackgroundColor:
                        AppTheme.success.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: Icon(
                    canConfirm
                        ? Icons.check_circle_rounded
                        : Icons.block_rounded,
                    size: 28,
                    color: Colors.white.withValues(
                        alpha: canConfirm ? 1 : 0.6),
                  ),
                  label: Text(
                    // F029: el botón muestra el total efectivo (no el
                    // pasado por constructor) para que el cajero vea
                    // exactamente lo que va a cobrar.
                    'Registrar venta por $effectiveFormatted',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(
                          alpha: canConfirm ? 1 : 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // F030 — tile "Cliente". Muestra el cliente asociado a la venta
  // (avatar circular + nombre/teléfono) o "Sin cliente" cuando es
  // anónima. Tocarlo abre el selector reutilizable; el cliente elegido
  // se guarda en CartController.selectedCustomer y su `customer_id`
  // viaja con la venta. El selectedCustomer vive en el controller para
  // que el payload de createSale lo lea de una sola fuente.
  Widget _buildCustomerTile(CartController ctrl) {
    final customer = ctrl.selectedCustomer;
    final hasCustomer = customer != null;
    return InkWell(
      key: const Key('checkout_customer_tile'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openCustomerSelector(ctrl),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: hasCustomer
                  ? AppTheme.primary.withValues(alpha: 0.14)
                  : const Color(0xFFE5E0DA),
              child: Icon(
                hasCustomer
                    ? Icons.person_rounded
                    : Icons.person_outline_rounded,
                color: hasCustomer ? AppTheme.primary : Colors.grey.shade600,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cliente',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasCustomer ? customer.name : 'Sin cliente',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: hasCustomer
                          ? AppTheme.textPrimary
                          : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasCustomer && customer.phone.isNotEmpty)
                    Text(
                      customer.phone,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                ],
              ),
            ),
            if (hasCustomer)
              IconButton(
                key: const Key('checkout_customer_clear'),
                tooltip: 'Quitar cliente',
                icon: Icon(Icons.close_rounded,
                    color: Colors.grey.shade600, size: 22),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ctrl.setCustomer(null);
                },
              )
            else
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.primary, size: 26),
          ],
        ),
      ),
    );
  }

  /// Abre el selector de cliente y guarda la elección en el controller.
  Future<void> _openCustomerSelector(CartController ctrl) async {
    HapticFeedback.lightImpact();
    final picked = await showCustomerSelectorSheet(context);
    if (picked != null) {
      ctrl.setCustomer(picked);
    }
  }

  // F029 — selector "Tipo de precio". Vertical radio para que los
  // 4 labels (retail + 3 tiers, potencialmente largos) entren bien
  // en 360dp sin overflow horizontal. El selectedPriceTier vive en
  // CartController para que totalForTier + subtotalForItem usen el
  // mismo valor; al tocar un option llamamos setPriceTier y el
  // controller dispara notifyListeners que rebuildea esta pantalla
  // (suscrita via context.watch en build).
  Widget _buildPriceTierSelector(CartController ctrl) {
    final options = <(String, String)>[
      ('retail', 'Cliente final'),
      ('tier_1', _tier1Name),
      ('tier_2', _tier2Name),
      ('tier_3', _tier3Name),
    ];
    final selected = ctrl.selectedPriceTier;
    return Container(
      key: const Key('checkout_price_tier_selector'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_offer_rounded,
                  size: 22, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tipo de precio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final opt in options)
            _TierRadioTile(
              key: Key('tier_option_${opt.$1}'),
              value: opt.$1,
              label: opt.$2,
              selected: selected == opt.$1,
              onTap: () {
                HapticFeedback.lightImpact();
                ctrl.setPriceTier(opt.$1);
              },
            ),
        ],
      ),
    );
  }

  // F029 — fila de resumen con tier-aware pricing. Cuando la capacidad
  // está OFF o no hay CartController (tests legacy), respeta el subtotal
  // pre-F029 sin cambios.
  Widget _buildSummaryRow(CartItem item, {CartController? cartCtrl}) {
    final tieredActive = _enablePriceTiers && cartCtrl != null;
    final subtotal = tieredActive
        ? cartCtrl.subtotalForItem(item)
        : item.subtotal;
    final usingRetailFallback =
        tieredActive && cartCtrl.itemUsingRetailFallback(item);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.quantity}× ${item.product.name}',
                style: const TextStyle(
                    fontSize: 17, color: AppTheme.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (usingRetailFallback)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    key: Key(
                        'checkout_retail_fallback_${item.product.uuid}'),
                    '⚠ usando precio retail',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(_formatCOP(subtotal.round()),
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary)),
      ],
    );
  }

  Future<void> _confirmSale() async {
    HapticFeedback.mediumImpact();

    // Fiar branch — special UX path. The picker selects an existing
    // fiado or opens a brand-new credit account before the sale is
    // committed; this branch never falls through to the generic
    // close-sale path.
    if (_selectedMethodKey == _kFiar) {
      final active = context.read<ActiveFiadoService>();
      if (active.hasActive) {
        final accountId = active.accountId!;
        active.clear();
        await _appendToFiadoById(accountId,
            customerName: active.customerName);
        return;
      }
      if (!mounted) return;
      await _showFiadoChoiceSheet();
      return;
    }

    // Fallback cash chip (tenant has no methods configured yet) or
    // a stale state with no method selected. Either way we treat
    // the sale as plain cash and close immediately.
    if (_selectedMethodKey == _kFallbackCash || _selectedMethod == null) {
      Navigator.of(context).pop(
        const CheckoutResult(confirmed: true, paymentMethod: 'cash'),
      );
      return;
    }

    final method = _selectedMethod!;

    // Cash provider configured by the merchant — close immediately.
    if (method.provider == 'cash') {
      Navigator.of(context).pop(
        CheckoutResult(
          confirmed: true,
          paymentMethod: method.name.toLowerCase(),
        ),
      );
      return;
    }

    // Any non-cash method that has a QR image attached must surface
    // the QR to the customer before the cashier confirms reception.
    // This single rule replaces the old hardcoded 'transfer' branch
    // — Nequi, Daviplata, Bancolombia QR, custom merchant QRs all
    // route through the same modal.
    final qrUrl = method.qrImageUrl?.trim() ?? '';
    if (qrUrl.isNotEmpty) {
      final confirmed = await _showMethodQrDialog(method);
      if (confirmed != true) return;
      if (!mounted) return;
      Navigator.of(context).pop(
        CheckoutResult(
          confirmed: true,
          paymentMethod: method.name.toLowerCase(),
          receiptImageUrl: _receiptUrl,
        ),
      );
      return;
    }

    // Non-cash method with no QR configured — close as a plain
    // electronic payment. The cashier confirms manually with the
    // customer (e.g. card terminal print-out).
    Navigator.of(context).pop(
      CheckoutResult(
        confirmed: true,
        paymentMethod: method.name.toLowerCase(),
        receiptImageUrl: _receiptUrl,
      ),
    );
  }

  /// Shows the merchant-configured QR for [method] in a modal. The
  /// cashier taps "Recibí el pago" once the customer's transfer is
  /// visible in the wallet app. Returns true on confirm, null/false
  /// on dismiss.
  Future<bool?> _showMethodQrDialog(LocalPaymentMethod method) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return _MethodQrSheet(
          method: method,
          amount: widget.total,
          formattedTotal: widget.formattedTotal,
        );
      },
    );
  }

  /// Single entry point for the two fiado flows: open a brand-new account
  /// (handshake) or append to one that's already open. Both choices are
  /// presented with the same visual weight so the cashier can decide fast.
  Future<void> _showFiadoChoiceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const Text('¿A quién se le fía?',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87)),
              const SizedBox(height: 4),
              Text('Total: ${widget.formattedTotal}',
                  style: const TextStyle(
                      fontSize: 16, color: AppTheme.textSecondary)),
              const SizedBox(height: 18),
              _FiadoChoiceTile(
                icon: Icons.person_add_rounded,
                color: const Color(0xFFF59E0B),
                title: 'Abrir cuenta nueva',
                subtitle:
                    CreditLabels.of(context).newAccountDescription,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  // PIN gate applies only when opening a new line of credit.
                  final role = context.read<RoleManager>();
                  if (!role.canGrantFiadoWithoutPin) {
                    final ok = await askOwnerPin(
                      context,
                      subtitle:
                          CreditLabels.of(context).openNewAccountPinHint,
                    );
                    if (!ok) return;
                  }
                  if (!mounted) return;
                  _showFiadoHandshake();
                },
              ),
              const SizedBox(height: 10),
              _FiadoChoiceTile(
                icon: Icons.menu_book_rounded,
                color: const Color(0xFF6D28D9),
                title: 'Agregar a una cuenta ya abierta',
                subtitle:
                    'Para un cliente que ya le fiaba. Se suma a su deuda, sin nuevo link.',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  await _showActiveFiadoPicker();
                },
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Searchable list of every open fiado for this tenant. One tap appends
  /// the current sale total to the selected account and closes checkout.
  Future<void> _showActiveFiadoPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: _ActiveFiadoPickerContent(
            scrollController: scrollCtrl,
            saleTotalFormatted: widget.formattedTotal,
            onSelect: (accountId, customerName) async {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              await _appendToFiadoById(accountId, customerName: customerName);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _appendToFiadoById(String accountId,
      {String? customerName}) async {
    final total = widget.total.round();
    final api = ApiService(AuthService());
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );
    try {
      await api.appendToFiado(accountId, totalAmount: total);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loader
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(
        CheckoutResult(
          confirmed: true,
          paymentMethod: 'credit',
          creditAccountId: accountId,
        ),
      );
    } on AppError catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loader
      HapticFeedback.heavyImpact();
      final labels = CreditLabels.of(context);
      final who = customerName == null || customerName.isEmpty
          ? labels.theAccountArticle
          : '${labels.theAccountArticle} de $customerName';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo agregar a $who: ${e.message}',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showFiadoHandshake() {
    final nameCtrl =
        TextEditingController(text: widget.prefillCustomerName ?? '');
    final phoneCtrl =
        TextEditingController(text: widget.prefillCustomerPhone ?? '');
    final emailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Icon(Icons.menu_book_rounded,
                  color: Color(0xFFF59E0B), size: 40),
              const SizedBox(height: 12),
              Text(CreditLabels.of(context).registrarLabel,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 4),
              Text('Total: ${widget.formattedTotal}',
                  style: const TextStyle(fontSize: 18,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: 20, color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Nombre del cliente',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 20, color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Celular / WhatsApp',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 20, color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico (opcional)',
                  prefixIcon: Icon(Icons.email_rounded),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final hasPhone = phoneCtrl.text.trim().length >= 7;
                    final hasEmail = emailCtrl.text.trim().contains('@');
                    if (nameCtrl.text.trim().isEmpty || (!hasPhone && !hasEmail)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Ingrese nombre y al menos celular o correo',
                            style: TextStyle(fontSize: 16)),
                        backgroundColor: AppTheme.warning,
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    Navigator.of(ctx).pop();
                    await _initFiado(
                      nameCtrl.text.trim(),
                      phoneCtrl.text.trim(),
                      emailCtrl.text.trim(),
                    );
                  },
                  icon: const Icon(Icons.send_rounded, size: 24),
                  label: const Text('Enviar link de aceptacion',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initFiado(String name, String phone, String email) async {
    final idempotencyKey = DateTime.now().millisecondsSinceEpoch.toString();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FiadoWaitingRoom(
        total: widget.formattedTotal,
        customerName: name,
        customerPhone: phone,
        customerEmail: email,
        totalAmount: widget.total.round(),
        idempotencyKey: idempotencyKey,
        // The waiting room propagates the backend credit_id so the Sale
        // that's about to be created in Isar + synced to /sales can be
        // attributed to this exact fiado. Without this link the public
        // statement can't itemize the purchase.
        onAccepted: (creditId, acceptedByCustomer) {
          Navigator.of(context).pop();
          Navigator.of(context).pop(
            CheckoutResult(
              confirmed: true,
              paymentMethod: 'credit',
              creditAccountId: creditId,
              fiadoPending: !acceptedByCustomer,
              // Propagate the form values so POS can render
              // "Fiado: <name>" on the locked slot bubble without a
              // round-trip to /credits/<id>.
              customerName: name,
              customerPhone: phone,
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _PaymentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _PaymentChip({
    super.key,
    required this.icon, required this.label,
    required this.selected, required this.onTap, this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.1) : AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c : AppTheme.borderColor,
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? c : AppTheme.textSecondary, size: 24),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(
                fontSize: 18,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? c : AppTheme.textPrimary)),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, color: c, size: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class _BillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BillChip({
    required this.label, required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF3B82F6)
                : const Color(0xFFD6D0C8),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(label, style: TextStyle(
            fontSize: 18,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? const Color(0xFF3B82F6)
                : Colors.black87)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _FiadoWaitingRoom extends StatefulWidget {
  final String total;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final int totalAmount;
  final String idempotencyKey;
  /// Called when the handshake completes OR the cashier closes the
  /// waiting room via "Seguir vendiendo". Receives (credit_id,
  /// acceptedByCustomer). acceptedByCustomer is true when polling saw
  /// the accept or when the backend merged into an already-accepted
  /// account; false when the cashier walked away before acceptance —
  /// the UI uses this to show pending vs confirmed success variants.
  final void Function(String? creditId, bool acceptedByCustomer) onAccepted;

  const _FiadoWaitingRoom({
    required this.total,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.totalAmount,
    required this.idempotencyKey,
    required this.onAccepted,
  });

  @override
  State<_FiadoWaitingRoom> createState() => _FiadoWaitingRoomState();
}

class _FiadoWaitingRoomState extends State<_FiadoWaitingRoom> {
  late final ApiService _api;
  // States: sending, link_sent, link_opened, accepted, error
  String _status = 'sending';
  String? _waLink;
  String? _emailUrl;
  String? _acceptUrl;
  String? _fiadoToken;
  String? _creditId;
  String? _errorMsg;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _sendFiado();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendFiado() async {
    try {
      final res = await _api.initFiado(
        customerName: widget.customerName,
        customerPhone: widget.customerPhone,
        customerEmail: widget.customerEmail,
        totalAmount: widget.totalAmount,
        idempotencyKey: widget.idempotencyKey,
      );
      if (!mounted) return;
      // Backend detected an accepted open fiado for this customer and
      // asks the cashier to confirm the append (instead of silently
      // merging). Show a dialog with the current balance and let them
      // decide. On confirm, call /credits/:id/append; on cancel, close
      // the handshake — the cashier can pick a different option.
      if (res['needs_confirmation'] == true) {
        final confirmed = await _confirmAppendToExisting(res);
        if (!mounted) return;
        if (confirmed == true) {
          final existingId = res['existing_credit_id'] as String?;
          if (existingId != null) {
            try {
              await _api.appendToFiado(
                existingId,
                totalAmount: widget.totalAmount,
              );
              if (!mounted) return;
              HapticFeedback.mediumImpact();
              // The merge path appends to an already-accepted account —
              // the customer authorized this line of credit earlier.
              widget.onAccepted(existingId, true);
              return;
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _status = 'error';
                _errorMsg = e.toString();
              });
              return;
            }
          }
        }
        // User cancelled — close the waiting room with no sale.
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _status = 'link_sent';
        _waLink = res['whatsapp_url'] as String?;
        _emailUrl = res['email_url'] as String?;
        _acceptUrl = res['accept_url'] as String?;
        _fiadoToken = res['fiado_token'] as String?;
        _creditId = res['credit_id'] as String?;
      });
      // Open WhatsApp or Email automatically
      if (_waLink != null) {
        launchUrl(Uri.parse(_waLink!), mode: LaunchMode.externalApplication);
      } else if (_emailUrl != null) {
        launchUrl(Uri.parse(_emailUrl!), mode: LaunchMode.externalApplication);
      }
      // Start polling every 5 seconds
      _startPolling();
    } catch (e) {
      debugPrint('FIADO INIT ERROR: $e');
      if (mounted) {
        setState(() {
          _status = 'error';
          _errorMsg = e.toString();
        });
      }
    }
  }

  /// Confirm dialog shown when the customer already has an accepted open
  /// fiado and the cashier tried to open a new one. Makes the "line of
  /// credit" semantics visible — nothing happens silently.
  Future<bool?> _confirmAppendToExisting(Map<String, dynamic> res) {
    final name = (res['customer_name'] as String?) ?? widget.customerName;
    final balance = (res['existing_balance'] as num?)?.toInt() ?? 0;
    final added = (res['requested_amount'] as num?)?.toInt() ?? widget.totalAmount;
    final newTotal = (res['projected_new_total'] as num?)?.toInt() ?? (balance + added);
    String fmt(int v) {
      if (v == 0) return '\$0';
      final s = v.abs().toString();
      final buf = StringBuffer(v < 0 ? '-\$' : '\$');
      final start = s.length % 3;
      if (start > 0) buf.write(s.substring(0, start));
      for (int i = start; i < s.length; i += 3) {
        if (i > 0) buf.write('.');
        buf.write(s.substring(i, i + 3));
      }
      return buf.toString();
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.menu_book_rounded,
                color: Color(0xFF6D28D9), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text('Cuenta ya abierta',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$name ya tiene una cuenta abierta que fue aceptada.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6D28D9).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Saldo actual', fmt(balance),
                      color: const Color(0xFFEA580C)),
                  const SizedBox(height: 4),
                  _row('Esta venta', '+ ${fmt(added)}',
                      color: Colors.black87),
                  const Divider(height: 18),
                  _row('Nuevo total', fmt(newTotal),
                      color: const Color(0xFF6D28D9), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Al confirmar, la venta se suma a su cuenta sin enviarle un link nuevo (ya había autorizado esta línea de crédito).',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 10),
            ),
            child: const Text('Sumar a su cuenta',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {required Color color, bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 18 : 15,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: color)),
      ],
    );
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_fiadoToken == null) return;
    try {
      final res = await _api.checkFiadoStatus(_fiadoToken!);
      final status = res['fiado_status'] as String? ?? '';
      if (!mounted) return;
      if (status != _status) {
        setState(() => _status = status);
      }
      if (status == 'accepted') {
        _pollTimer?.cancel();
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 1500));
        // Polling saw the customer accept.
        if (mounted) widget.onAccepted(_creditId, true);
      }
    } catch (_) {}
  }

  void _resendWhatsApp() {
    if (_waLink != null) {
      HapticFeedback.lightImpact();
      launchUrl(Uri.parse(_waLink!), mode: LaunchMode.externalApplication);
    }
  }

  /// Launch the device SMS app with the accept-URL prefilled. Phone is
  /// normalized (non-digits stripped, +57 prepended for 10-digit Colombian
  /// locals) to maximize chance the default SMS app resolves a recipient.
  void _resendSms() {
    if (_acceptUrl == null || widget.customerPhone.isEmpty) return;
    HapticFeedback.lightImpact();
    final digits = widget.customerPhone.replaceAll(RegExp(r'\D'), '');
    final full = digits.startsWith('57') ? digits : '57$digits';
    final body =
        'Hola ${widget.customerName}, ${widget.total} le fue ${CreditLabels.of(context).nounSingular}. '
        'Acepte aquí: $_acceptUrl';
    final uri = Uri(
      scheme: 'sms',
      path: '+$full',
      queryParameters: {'body': body},
    );
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _copyLink() {
    if (_acceptUrl != null) {
      Clipboard.setData(ClipboardData(text: _acceptUrl!));
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link copiado al portapapeles',
            style: TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status icon + animation
          _buildStatusIcon(),
          const SizedBox(height: 16),
          // Status text
          _buildStatusText(),
          const SizedBox(height: 8),
          _buildStatusSubtext(),

          // Resend actions (only when waiting)
          if (_status == 'link_sent' || _status == 'link_opened') ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_waLink != null)
                  _resendBtn(Icons.chat_rounded, 'WhatsApp',
                      const Color(0xFF25D366), _resendWhatsApp),
                if (widget.customerPhone.isNotEmpty && _acceptUrl != null)
                  _resendBtn(Icons.sms_rounded, 'SMS',
                      const Color(0xFF3B82F6), _resendSms),
                if (_emailUrl != null)
                  _resendBtn(Icons.email_rounded, 'Correo',
                      const Color(0xFFEA580C), () {
                    HapticFeedback.lightImpact();
                    launchUrl(Uri.parse(_emailUrl!),
                        mode: LaunchMode.externalApplication);
                  }),
                _resendBtn(Icons.copy_rounded, 'Copiar link',
                    AppTheme.primary, _copyLink),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6D28D9).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF6D28D9).withValues(alpha: 0.25),
                    width: 1),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Color(0xFF6D28D9), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Puedes seguir vendiendo. Cuando el cliente acepte, '
                      'te llegará una notificación y podrás confirmarlo '
                      'en el Cuaderno.',
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Color(0xFF4C1D95)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                // Cashier walks away to attend other clients — items were
                // already given, so the sale is real. Register it now
                // linked to the pending fiado. The credit_account stays
                // in status='pending' until the customer accepts. The
                // pending fiado is visible in the Cuaderno's "Pendientes"
                // tab + a badge on the POS Cuaderno icon.
                onPressed: () {
                  _pollTimer?.cancel();
                  // Cashier walks away before the customer accepted —
                  // fiado stays pending until the accept endpoint fires.
                  widget.onAccepted(_creditId, false);
                },
                icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                label: const Text('Seguir vendiendo',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],

          if (_status == 'error') ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar',
                  style: TextStyle(fontSize: 16, color: AppTheme.error)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resendBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(fontSize: 14, color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      ),
    );
  }

  Widget _buildStatusIcon() {
    return switch (_status) {
      'sending' => const SizedBox(width: 48, height: 48,
          child: CircularProgressIndicator(
              color: Color(0xFFF59E0B), strokeWidth: 3)),
      'link_sent' => const Icon(Icons.done_all_rounded,
          color: AppTheme.textSecondary, size: 48),
      'link_opened' => const Icon(Icons.visibility_rounded,
          color: Color(0xFF3B82F6), size: 48),
      'accepted' => const Icon(Icons.check_circle_rounded,
          color: AppTheme.success, size: 56),
      _ => const Icon(Icons.error_outline_rounded,
          color: AppTheme.error, size: 48),
    };
  }

  Widget _buildStatusText() {
    final text = switch (_status) {
      'sending' => 'Enviando link a ${widget.customerName}...',
      'link_sent' => 'Link enviado',
      'link_opened' => '${widget.customerName} esta leyendo...',
      'accepted' => 'Deuda aceptada!',
      _ => CreditLabels.of(context).createErrorMsg,
    };
    return Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: _status == 'error' ? AppTheme.error : Colors.black87,
        ));
  }

  Widget _buildStatusSubtext() {
    final labels = CreditLabels.of(context);
    final text = switch (_status) {
      'sending' => labels.sendingStatusMsg,
      'link_sent' =>
          'Esperando que ${widget.customerName} abra el link enviado al ${widget.customerPhone}',
      'link_opened' => labels.reviewingTermsMsg(widget.customerName),
      'accepted' => 'Puede entregar los productos',
      _ => _errorMsg != null && _errorMsg!.isNotEmpty
          ? 'Detalle: $_errorMsg\nIntente de nuevo o registre sin firma'
          : 'Intente de nuevo o registre sin firma',
    };
    return Text(text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary));
  }
}

/// Two-option card for the "¿A quién se le fía?" picker. Big icon, title,
/// and a descriptive subtitle so the cashier can read the difference
/// without having to think about "handshake vs append" — the business
/// meaning is spelled out in Spanish.
class _FiadoChoiceTile extends StatelessWidget {
  const _FiadoChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable list of active (open+accepted) fiados. Loads once on init
/// from GET /api/v1/credits?status=open and filters client-side by name
/// or phone. Tapping a row returns via onSelect(accountId, customerName).
class _ActiveFiadoPickerContent extends StatefulWidget {
  const _ActiveFiadoPickerContent({
    required this.scrollController,
    required this.saleTotalFormatted,
    required this.onSelect,
  });

  final ScrollController scrollController;
  final String saleTotalFormatted;
  final void Function(String accountId, String customerName) onSelect;

  @override
  State<_ActiveFiadoPickerContent> createState() =>
      _ActiveFiadoPickerContentState();
}

class _ActiveFiadoPickerContentState
    extends State<_ActiveFiadoPickerContent> {
  late final ApiService _api;
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    try {
      // Pull every non-cancelled, non-paid account and filter
      // client-side. Sending status='open' alone hid customers who'd
      // already paid an abono (status='partial'), making it impossible
      // to append a new sale to a fiado that wasn't pristine. The
      // backend's AppendToFiado endpoint accepts status='open' OR
      // 'partial' equivalently, so the picker should match.
      final res = await _api.fetchCredits(perPage: 200);
      final raw =
          (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final list = raw.where((c) {
        final status = (c['status'] as String?) ?? '';
        return status == 'open' || status == 'partial';
      }).toList(growable: false);
      if (mounted) setState(() { _all = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num amount) {
    final v = amount.round();
    if (v == 0) return '\$0';
    final s = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-\$' : '\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return _all;
    final q = _query.trim().toLowerCase();
    return _all.where((c) {
      final cust = (c['customer'] as Map<String, dynamic>?) ?? const {};
      final name = (cust['name'] as String? ?? '').toLowerCase();
      final phone = (cust['phone'] as String? ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD6D0C8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Elegir a quién agregar',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                Text(
                    'Se sumará ${widget.saleTotalFormatted} al saldo del cliente.',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 12),
                TextField(
                  autofocus: false,
                  style: const TextStyle(fontSize: 18),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente por nombre o celular',
                    hintStyle: TextStyle(
                        fontSize: 16, color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppTheme.primary),
                    filled: true,
                    fillColor: const Color(0xFFF8F7F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : _filtered.isEmpty
                    ? _empty()
                    : ListView.separated(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tile(_filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final hasData = _all.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 52,
                color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(
              hasData
                  ? 'Ningún cliente coincide con esa búsqueda'
                  : 'Aún no hay cuentas abiertas. Use "Abrir cuenta nueva".',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, color: AppTheme.textSecondary, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> credit) {
    final cust = (credit['customer'] as Map<String, dynamic>?) ?? const {};
    final name = cust['name'] as String? ?? 'Sin nombre';
    final phone = cust['phone'] as String? ?? '';
    final total = (credit['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (credit['paid_amount'] as num?)?.toInt() ?? 0;
    final balance = total - paid;
    final accountId = credit['id'] as String;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onSelect(accountId, name),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
                color: const Color(0xFFEDE8E0), width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    const Color(0xFF6D28D9).withValues(alpha: 0.12),
                child: Text(initial,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6D28D9))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(
                      phone.isNotEmpty ? phone : 'Sin celular',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Debe',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  Text(_fmt(balance),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFEA580C))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic QR sheet for any tenant-configured payment method that
/// has a [LocalPaymentMethod.qrImageUrl] attached. Shows the merchant
/// QR image, optional account details (e.g. Nequi number, account
/// holder), and a "Recibí el pago" CTA that pops `true`. Pops `false`
/// on cancel and `null` if dismissed via the OS gesture/back button.
///
/// Note: this widget is method-agnostic by design — there is no
/// hardcoded branching for Nequi/Daviplata/Bancolombia. The only
/// thing that changes per method is the icon + accent colour, which
/// are derived from [LocalPaymentMethod.provider]/[LocalPaymentMethod.name]
/// via the same helpers the chip strip uses.
class _MethodQrSheet extends StatefulWidget {
  const _MethodQrSheet({
    required this.method,
    required this.amount,
    required this.formattedTotal,
  });

  final LocalPaymentMethod method;
  final double amount;
  final String formattedTotal;

  @override
  State<_MethodQrSheet> createState() => _MethodQrSheetState();
}

class _MethodQrSheetState extends State<_MethodQrSheet> {
  bool _confirming = false;

  Color get _accent {
    final p = (widget.method.provider ?? '').toLowerCase();
    final n = widget.method.name.toLowerCase();
    if (p == 'nequi' || n.contains('nequi')) return const Color(0xFFE5007E);
    if (p == 'daviplata' || n.contains('daviplata')) {
      return const Color(0xFFE2001A);
    }
    if (n.contains('bancolombia')) return const Color(0xFFFDDA24);
    if (n.contains('davivienda')) return const Color(0xFFED1C24);
    if (n.contains('bbva')) return const Color(0xFF004481);
    return AppTheme.primary;
  }

  IconData get _icon {
    final p = (widget.method.provider ?? '').toLowerCase();
    final n = widget.method.name.toLowerCase();
    if (p == 'nequi' || n.contains('nequi')) {
      return Icons.smartphone_rounded;
    }
    if (p == 'daviplata' || n.contains('daviplata')) {
      return Icons.smartphone_rounded;
    }
    if (p == 'qr' || n.contains('qr')) return Icons.qr_code_rounded;
    if (n.contains('bancolombia') || n.contains('banco')) {
      return Icons.account_balance_rounded;
    }
    return Icons.account_balance_wallet_rounded;
  }

  Future<void> _copyAccountDetails() async {
    final details = widget.method.accountDetails?.trim() ?? '';
    if (details.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: details));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Datos de cuenta copiados',
          style: TextStyle(fontSize: 15)),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final qrUrl = widget.method.qrImageUrl?.trim() ?? '';
    final details = widget.method.accountDetails?.trim() ?? '';
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.7,
      maxChildSize: 0.98,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFBF7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                child: Column(
                  children: [
                    // Method chip — name + icon, accent-coloured.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon, color: _accent, size: 20),
                          const SizedBox(width: 8),
                          Text(widget.method.name,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _accent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Escanee para pagar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.success.withValues(alpha: 0.35),
                            width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded,
                              color: AppTheme.success, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Total: ${widget.formattedTotal}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // QR image — loads the merchant-uploaded asset.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 260,
                        height: 260,
                        child: Image.network(
                          qrUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                  color: AppTheme.primary),
                            );
                          },
                          errorBuilder: (ctx, err, stack) => const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image_rounded,
                                    size: 64,
                                    color: AppTheme.textSecondary),
                                SizedBox(height: 8),
                                Text(
                                  'No se pudo cargar el QR',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Account details — only render if the merchant
                    // typed something into the admin form. Selectable
                    // monospace so the customer can read it aloud.
                    if (details.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFEDE8E0), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Si no puede escanear:',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary
                                        .withValues(alpha: 0.9))),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    details,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                      color: AppTheme.textPrimary,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _copyAccountDetails,
                                  icon: const Icon(Icons.copy_rounded,
                                      size: 18),
                                  label: const Text('Copiar',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _accent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _confirming
                            ? null
                            : () {
                                setState(() => _confirming = true);
                                HapticFeedback.heavyImpact();
                                Navigator.of(context).pop(true);
                              },
                        icon: const Icon(Icons.check_circle_rounded,
                            size: 26),
                        label: const Text(
                            'Recibí el pago',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          elevation: 6,
                          shadowColor:
                              AppTheme.success.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _confirming
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// F029 — radio tile vertical para el selector "Tipo de precio".
// Objetivo táctil 56dp (≥48 mínimo). Labels en español, fontSize 17
// (≥17 por la guía de gerontodiseño). Usado solo cuando
// enable_price_tiers está ON.
class _TierRadioTile extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TierRadioTile({
    super.key,
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppTheme.primary : const Color(0xFFB0A99A),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Center(
                      child: Icon(Icons.circle,
                          size: 10, color: AppTheme.primary),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
