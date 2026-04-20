import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/cart_item.dart';
import '../../services/active_fiado_service.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/role_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/owner_pin_dialog.dart';

class CheckoutResult {
  final bool confirmed;
  final String paymentMethod;
  /// When the cashier chose "Agregar a cuenta existente", this is the id
  /// of the fiado we appended to. POS forwards it when syncing the sale
  /// so the backend can link the sale to the account and the public
  /// statement can show the itemized detail.
  final String? creditAccountId;
  const CheckoutResult({
    required this.confirmed,
    required this.paymentMethod,
    this.creditAccountId,
  });
}

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> items;
  final String formattedTotal;
  final double total;

  const CheckoutScreen({
    super.key,
    required this.items,
    required this.formattedTotal,
    required this.total,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedMethod = 'cash';
  double _amountTendered = 0;
  final _manualCtrl = TextEditingController();

  static const _denominations = [2000, 5000, 10000, 20000, 50000, 100000];

  double get _change => _amountTendered - widget.total;
  bool get _isExact => (_amountTendered - widget.total).abs() < 1;
  bool get _isCash => _selectedMethod == 'cash';
  bool get _canConfirm =>
      !_isCash || _amountTendered >= widget.total;

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
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
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
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${widget.items[i].quantity}× ${widget.items[i].product.name}',
                                    style: const TextStyle(fontSize: 17,
                                        color: AppTheme.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(widget.items[i].formattedSubtotal,
                                    style: const TextStyle(fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary)),
                              ],
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
                        Text(widget.formattedTotal,
                            style: const TextStyle(fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Payment methods ───────────────────────────────
                  const Text('Método de pago',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _PaymentChip(
                        icon: Icons.payments_rounded,
                        label: 'Efectivo',
                        selected: _selectedMethod == 'cash',
                        onTap: () => setState(() => _selectedMethod = 'cash'),
                      ),
                      _PaymentChip(
                        icon: Icons.phone_android_rounded,
                        label: 'Transferencia',
                        selected: _selectedMethod == 'transfer',
                        onTap: () => setState(() => _selectedMethod = 'transfer'),
                      ),
                      _PaymentChip(
                        icon: Icons.credit_card_rounded,
                        label: 'Tarjeta',
                        selected: _selectedMethod == 'card',
                        onTap: () => setState(() => _selectedMethod = 'card'),
                      ),
                      _PaymentChip(
                        icon: Icons.menu_book_rounded,
                        label: 'Fiar',
                        selected: _selectedMethod == 'credit',
                        onTap: () => setState(() => _selectedMethod = 'credit'),
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
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
                        // "Exacto" button
                        _BillChip(
                          label: 'Exacto',
                          selected: _isExact,
                          onTap: () => _setTendered(widget.total),
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
                  onPressed: _canConfirm ? _confirmSale : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    disabledBackgroundColor:
                        AppTheme.success.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: Icon(
                    _canConfirm
                        ? Icons.check_circle_rounded
                        : Icons.block_rounded,
                    size: 28,
                    color: Colors.white.withValues(
                        alpha: _canConfirm ? 1 : 0.6),
                  ),
                  label: Text(
                    'Registrar venta por ${widget.formattedTotal}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(
                          alpha: _canConfirm ? 1 : 0.6),
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

  Future<void> _confirmSale() async {
    HapticFeedback.mediumImpact();

    if (_selectedMethod == 'credit') {
      // Legacy fast-path: if some upstream screen staged an active fiado
      // before arriving here, honor it silently. In the new UX no screen
      // sets this — the picker below handles both "new" and "existing".
      final active = context.read<ActiveFiadoService>();
      if (active.hasActive) {
        final accountId = active.accountId!;
        active.clear();
        await _appendToFiadoById(accountId, customerName: active.customerName);
        return;
      }

      if (!mounted) return;
      await _showFiadoChoiceSheet();
      return;
    }

    Navigator.of(context).pop(
      CheckoutResult(confirmed: true, paymentMethod: _selectedMethod),
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
                    'Para un cliente que nunca le ha fiado. Se envía un link para que acepte.',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  // PIN gate applies only when opening a new line of credit.
                  final role = context.read<RoleManager>();
                  if (!role.canGrantFiadoWithoutPin) {
                    final ok = await askOwnerPin(
                      context,
                      subtitle:
                          'Para abrir un fiado nuevo, pida al propietario que ingrese su PIN de 4 dígitos.',
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
      final who = customerName == null || customerName.isEmpty
          ? 'el fiado'
          : 'el fiado de $customerName';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo agregar a $who: ${e.message}',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showFiadoHandshake() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
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
              const Text('Registrar Fiado',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
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
        onAccepted: (creditId) {
          Navigator.of(context).pop();
          Navigator.of(context).pop(
            CheckoutResult(
              confirmed: true,
              paymentMethod: 'credit',
              creditAccountId: creditId,
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
  /// Called when the handshake completes (accepted) OR the cashier chose
  /// "Registrar venta sin firma". Receives the credit_id returned by
  /// /fiado/init so the resulting sale can be linked to the fiado. Null
  /// if the init call errored before we got an id back.
  final void Function(String? creditId) onAccepted;

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
              widget.onAccepted(existingId);
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
        if (mounted) widget.onAccepted(_creditId);
      }
    } catch (_) {}
  }

  void _resendWhatsApp() {
    if (_waLink != null) {
      HapticFeedback.lightImpact();
      launchUrl(Uri.parse(_waLink!), mode: LaunchMode.externalApplication);
    }
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
              children: [
                if (_waLink != null)
                  _resendBtn(Icons.chat_rounded, 'WhatsApp',
                      const Color(0xFF25D366), _resendWhatsApp),
                if (_emailUrl != null)
                  _resendBtn(Icons.email_rounded, 'Correo',
                      const Color(0xFF3B82F6), () {
                    HapticFeedback.lightImpact();
                    launchUrl(Uri.parse(_emailUrl!),
                        mode: LaunchMode.externalApplication);
                  }),
                _resendBtn(Icons.copy_rounded, 'Copiar link',
                    AppTheme.primary, _copyLink),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  _pollTimer?.cancel();
                  Navigator.of(context).pop(); // close dialog
                  Navigator.of(context).pop(); // back to POS
                },
                icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                label: const Text('Continuar vendiendo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                _pollTimer?.cancel();
                widget.onAccepted(_creditId);
              },
              child: const Text('Registrar venta sin firma',
                  style: TextStyle(fontSize: 14,
                      color: AppTheme.textSecondary)),
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
      _ => 'Error al crear fiado',
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
    final text = switch (_status) {
      'sending' => 'Preparando solicitud de fiado...',
      'link_sent' =>
          'Esperando que ${widget.customerName} abra el link enviado al ${widget.customerPhone}',
      'link_opened' =>
          '${widget.customerName} esta revisando los terminos del fiado',
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
      final res = await _api.fetchCredits(status: 'open', perPage: 200);
      final list =
          (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
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
