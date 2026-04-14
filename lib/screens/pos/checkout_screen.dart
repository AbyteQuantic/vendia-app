import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/cart_item.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class CheckoutResult {
  final bool confirmed;
  final String paymentMethod;
  const CheckoutResult({required this.confirmed, required this.paymentMethod});
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

  void _confirmSale() {
    HapticFeedback.mediumImpact();

    if (_selectedMethod == 'credit') {
      _showFiadoHandshake();
      return;
    }

    Navigator.of(context).pop(
      CheckoutResult(confirmed: true, paymentMethod: _selectedMethod),
    );
  }

  void _showFiadoHandshake() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty ||
                        phoneCtrl.text.trim().length < 7) return;
                    Navigator.of(ctx).pop();
                    await _initFiado(
                        nameCtrl.text.trim(), phoneCtrl.text.trim());
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

  Future<void> _initFiado(String customerName, String customerPhone) async {
    // Show waiting dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FiadoWaitingDialog(
        total: widget.formattedTotal,
        customerName: customerName,
        customerPhone: customerPhone,
        totalAmount: widget.total.round(),
        onAccepted: () {
          Navigator.of(context).pop(); // close dialog
          Navigator.of(context).pop(
            CheckoutResult(confirmed: true, paymentMethod: 'credit'),
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

class _FiadoWaitingDialog extends StatefulWidget {
  final String total;
  final String customerName;
  final String customerPhone;
  final int totalAmount;
  final VoidCallback onAccepted;

  const _FiadoWaitingDialog({
    required this.total,
    required this.customerName,
    required this.customerPhone,
    required this.totalAmount,
    required this.onAccepted,
  });

  @override
  State<_FiadoWaitingDialog> createState() => _FiadoWaitingDialogState();
}

class _FiadoWaitingDialogState extends State<_FiadoWaitingDialog> {
  late final ApiService _api;
  String _status = 'sending'; // sending, waiting, accepted, error
  String? _waLink;
  String? _fiadoToken;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _sendFiado();
  }

  Future<void> _sendFiado() async {
    try {
      final res = await _api.initFiado(
        customerName: widget.customerName,
        customerPhone: widget.customerPhone,
        totalAmount: widget.totalAmount,
      );
      if (mounted) {
        setState(() {
          _status = 'waiting';
          _waLink = res['whatsapp_url'] as String?;
          _fiadoToken = res['fiado_token'] as String?;
        });
        // Open WhatsApp
        if (_waLink != null) {
          launchUrl(Uri.parse(_waLink!), mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'error');
    }
  }

  Future<void> _checkStatus() async {
    if (_fiadoToken == null) return;
    try {
      final res = await _api.checkFiadoStatus(_fiadoToken!);
      final status = res['fiado_status'] as String? ?? '';
      if (status == 'accepted') {
        widget.onAccepted();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aun no ha aceptado. Intente de nuevo.',
                style: TextStyle(fontSize: 16)),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_status == 'sending') ...[
            const CircularProgressIndicator(color: Color(0xFFF59E0B)),
            const SizedBox(height: 16),
            const Text('Enviando solicitud...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black87)),
          ] else if (_status == 'waiting') ...[
            const Icon(Icons.hourglass_top_rounded,
                color: Color(0xFFF59E0B), size: 48),
            const SizedBox(height: 16),
            Text('Esperando que ${widget.customerName} acepte...',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 8),
            Text('Se envio un link por WhatsApp al ${widget.customerPhone}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _checkStatus,
                icon: const Icon(Icons.refresh_rounded, size: 22),
                label: const Text('Verificar estado',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Allow registering without signature (skip handshake)
                widget.onAccepted();
              },
              child: const Text('Registrar sin firma',
                  style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
            ),
          ] else if (_status == 'error') ...[
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.error, size: 48),
            const SizedBox(height: 16),
            const Text('Error al crear el fiado',
                style: TextStyle(fontSize: 18, color: AppTheme.error)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar', style: TextStyle(fontSize: 16)),
            ),
          ],
        ],
      ),
    );
  }
}
