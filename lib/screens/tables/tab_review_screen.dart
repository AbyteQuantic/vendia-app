import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Tab Review — tendero-side read of an open table ticket. Shows
/// items with their exact time of order, the abonos the customer
/// has already made (APPROVED only — pending abonos stay out of the
/// summary to avoid a "ya pagó" confusion), and a one-tap affordance
/// to register a manual cash/transfer abono.
///
/// We hit the PUBLIC live-tab endpoint so the cashier and the
/// customer look at the exact same numbers — divergence between the
/// POS view and the QR view was a real complaint on 2026-04-24.
class TabReviewScreen extends StatefulWidget {
  const TabReviewScreen({
    super.key,
    required this.sessionToken,
    required this.tableLabel,
    this.orderId,
  });

  final String sessionToken;
  final String tableLabel;
  // Needed for the "Registrar Abono Manual" authenticated POST.
  // Null disables the button — the cashier can still read the
  // cuenta but can't add abonos until the cart has synced.
  final String? orderId;

  @override
  State<TabReviewScreen> createState() => _TabReviewScreenState();
}

class _TabReviewScreenState extends State<TabReviewScreen> {
  late final ApiService _api;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final data = await _api.fetchPublicTableSession(widget.sessionToken);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'No pudimos cargar la cuenta: $e';
      });
    }
  }

  Future<void> _registerManualAbono() async {
    if (widget.orderId == null) return;
    final result = await showModalBottomSheet<_AbonoResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final methods = (_data?['payment_methods'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final remaining =
            (_data?['remaining_balance'] as num?)?.toDouble() ?? 0;
        return _ManualAbonoSheet(
          remaining: remaining,
          methods: methods,
        );
      },
    );
    if (result == null || !mounted) return;

    try {
      await _api.registerPartialPayment(
        orderId: widget.orderId!,
        amount: result.amount,
        paymentMethod: result.methodName,
        paymentMethodId: result.methodId,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abono registrado'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo registrar el abono: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _fmtCOP(num amount) {
    final v = amount.round();
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

  /// Pop up the customer-submitted screenshot full-screen so the
  /// tendero can verify the transfer landed before treating the
  /// abono as confirmed. The image is fetched from the same
  /// payment-receipts bucket the public catalog wrote it to.
  void _showReceipt(String url,
      {required String method, required double amount}) {
    if (url.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comprobante: ${method.isEmpty ? 'Pago' : method}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _fmtCOP(amount),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.65,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 240,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        height: 240,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: const Text(
                          'No pudimos cargar el comprobante.\n'
                          'Pídele al cliente que lo reenvíe.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Verifica que el monto y la cuenta destino coincidan antes de aprobar.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
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
        title: Text(
          widget.tableLabel,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.textPrimary),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: widget.orderId == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  key: const Key('tab_review_manual_abono'),
                  onPressed: _registerManualAbono,
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('Registrar Abono Manual'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.primary,
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 56, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    final data = _data!;
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final abonos = (data['partial_payments'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final total = (data['total'] as num?)?.toDouble() ?? 0;
    final paid = (data['paid_amount'] as num?)?.toDouble() ?? 0;
    final remaining = (data['remaining_balance'] as num?)?.toDouble() ??
        (total - paid);

    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _sectionTitle('Productos (${items.length})'),
          const SizedBox(height: 8),
          if (items.isEmpty)
            _emptyHint('Sin productos registrados todavía.')
          else
            ...items.map((it) => _ItemRow(
                  name: (it['product_name'] as String?) ?? '—',
                  quantity: (it['quantity'] as num?)?.toInt() ?? 1,
                  unitPrice: (it['unit_price'] as num?)?.toDouble() ?? 0,
                  subtotal: (it['subtotal'] as num?)?.toDouble() ?? 0,
                  emoji: (it['emoji'] as String?) ?? '',
                  time: _fmtTime(it['added_at'] as String?),
                  fmtCOP: _fmtCOP,
                )),
          const SizedBox(height: 24),
          _sectionTitle('Abonos registrados (${abonos.length})'),
          const SizedBox(height: 8),
          if (abonos.isEmpty)
            _emptyHint('Aún no hay abonos en esta cuenta.')
          else
            ...abonos.map((a) => _AbonoRow(
                  method: (a['payment_method'] as String?) ?? 'Efectivo',
                  amount: (a['amount'] as num?)?.toDouble() ?? 0,
                  time: _fmtTime(a['created_at'] as String?),
                  receiptUrl: (a['receipt_url'] as String?) ?? '',
                  onShowReceipt: () => _showReceipt(
                    a['receipt_url'] as String,
                    method: (a['payment_method'] as String?) ?? 'Efectivo',
                    amount: (a['amount'] as num?)?.toDouble() ?? 0,
                  ),
                  fmtCOP: _fmtCOP,
                )),
          const SizedBox(height: 24),
          _TotalsCard(
            total: total,
            paid: paid,
            remaining: remaining,
            fmtCOP: _fmtCOP,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppTheme.textSecondary,
          ),
        ),
      );

  Widget _emptyHint(String msg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          msg,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.emoji,
    required this.time,
    required this.fmtCOP,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final String emoji;
  final String time;
  final String Function(num) fmtCOP;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          if (emoji.isNotEmpty) ...[
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '$quantity × ${fmtCOP(unitPrice)}',
                    if (time.isNotEmpty) time,
                  ].join(' · '),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            fmtCOP(subtotal),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AbonoRow extends StatelessWidget {
  const _AbonoRow({
    required this.method,
    required this.amount,
    required this.time,
    required this.receiptUrl,
    required this.onShowReceipt,
    required this.fmtCOP,
  });

  final String method;
  final double amount;
  final String time;
  final String receiptUrl;
  final VoidCallback onShowReceipt;
  final String Function(num) fmtCOP;

  @override
  Widget build(BuildContext context) {
    final hasReceipt = receiptUrl.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${method.isEmpty ? 'Efectivo' : method}'
              '${time.isEmpty ? '' : ' · $time'}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (hasReceipt) ...[
            // Receipt viewer — eye icon next to the amount so the
            // tendero can verify the screenshot before treating
            // the abono as confirmed. Hidden when no proof was
            // attached (cash abonos, manual tendero entries).
            IconButton(
              key: const Key('abono_receipt_viewer'),
              tooltip: 'Ver comprobante',
              icon: const Icon(Icons.image_search_rounded,
                  size: 22, color: AppTheme.primary),
              onPressed: onShowReceipt,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            fmtCOP(amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.total,
    required this.paid,
    required this.remaining,
    required this.fmtCOP,
  });

  final double total;
  final double paid;
  final double remaining;
  final String Function(num) fmtCOP;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _row('Total', fmtCOP(total), primary: false),
          if (paid > 0)
            _row(
              'Abonos',
              '− ${fmtCOP(paid)}',
              color: AppTheme.success,
              primary: false,
            ),
          const Divider(height: 20),
          _row(
            'Saldo pendiente',
            fmtCOP(remaining),
            primary: true,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {required bool primary, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: primary ? 14 : 12,
              fontWeight: primary ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 1.2,
              color: color ?? AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: primary ? 26 : 16,
              fontWeight: FontWeight.w800,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AbonoResult {
  final double amount;
  final String methodName;
  final String methodId;
  _AbonoResult(this.amount, this.methodName, this.methodId);
}

class _ManualAbonoSheet extends StatefulWidget {
  const _ManualAbonoSheet({
    required this.remaining,
    required this.methods,
  });

  final double remaining;
  final List<Map<String, dynamic>> methods;

  @override
  State<_ManualAbonoSheet> createState() => _ManualAbonoSheetState();
}

class _ManualAbonoSheetState extends State<_ManualAbonoSheet> {
  late final TextEditingController _amountCtrl;
  String _methodName = 'Efectivo';
  String _methodId = '';

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.remaining.round().toString(),
    );
    if (widget.methods.isNotEmpty) {
      _methodName = (widget.methods.first['name'] as String?) ?? 'Efectivo';
      _methodId = (widget.methods.first['id'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0) return;
    Navigator.of(context).pop(_AbonoResult(amount, _methodName, _methodId));
  }

  @override
  Widget build(BuildContext context) {
    final methods = widget.methods;
    final chips = <Widget>[];
    // Always include Efectivo even if no digital methods are
    // configured — the common case for a cash-in-hand abono.
    final allMethodOptions = <Map<String, String>>[
      {'id': '', 'name': 'Efectivo'},
      ...methods.map((m) => {
            'id': (m['id'] as String?) ?? '',
            'name': (m['name'] as String?) ?? 'Método',
          }),
    ];
    for (final m in allMethodOptions) {
      final active = _methodName == m['name'] && _methodId == m['id'];
      chips.add(ChoiceChip(
        label: Text(m['name']!),
        selected: active,
        onSelected: (_) {
          setState(() {
            _methodName = m['name']!;
            _methodId = m['id']!;
          });
        },
      ));
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Registrar abono manual',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Monto',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Método',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.primary,
              ),
              child: const Text(
                'Guardar abono',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
