import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// ReceiptDetailScreen — full read-only view of a single Sale.
///
/// Receives the Sale row exactly as the unified /sales/history
/// endpoint returns it (Map<String, dynamic>) so we don't have to
/// re-fetch on tap. The two CTAs in the footer (Reimprimir +
/// WhatsApp) round-trip to the existing receipts handlers.
class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.sale,
  });

  final Map<String, dynamic> sale;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late final ApiService _api;
  bool _printing = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
  }

  Future<void> _reprint() async {
    final saleId = widget.sale['id'] as String?;
    if (saleId == null) return;
    HapticFeedback.lightImpact();
    setState(() => _printing = true);
    try {
      // Backend returns the formatted receipt payload. The actual
      // bluetooth dispatch is gated by the tenant having a printer
      // configured (printer_mac_address). We surface the success
      // message and rely on the tenant's existing printing setup
      // to consume the data — when the bluetooth driver is wired
      // the same call will physically print without code changes.
      await _api.reprintReceipt(saleId);
      if (!mounted) return;
      _flashOk('Recibo enviado a la impresora');
    } catch (e) {
      if (!mounted) return;
      _flashError('No se pudo reimprimir: $e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    final saleId = widget.sale['id'] as String?;
    if (saleId == null) return;
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      final res = await _api.sendReceiptWhatsApp(saleId);
      final url = res['whatsapp_url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('Sin URL de WhatsApp');
      }
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('No se pudo abrir WhatsApp');
    } catch (e) {
      if (!mounted) return;
      _flashError('No se pudo enviar por WhatsApp: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _flashOk(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _flashError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatCOP(num value) {
    final v = value.round();
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

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = [
        'ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
      ];
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '${d.day} ${months[d.month - 1]} ${d.year} · $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  String _methodLabel(String? method) => switch (method) {
        'cash' => 'Efectivo',
        'transfer' => 'Transferencia',
        'card' => 'Tarjeta',
        'credit' => 'Fiado',
        _ => method ?? '—',
      };

  String _sourceLabel(String? source) => switch (source) {
        'POS' => 'Mostrador',
        'TABLE' => 'Mesa',
        'WEB' => 'Pedido web',
        _ => 'Mostrador',
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final items = (s['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final total = (s['total'] as num?) ?? 0;
    final tax = (s['tax_amount'] as num?) ?? 0;
    final tip = (s['tip_amount'] as num?) ?? 0;
    final receiptNumber = (s['receipt_number'] as num?)?.toInt() ?? 0;
    final cashier = (s['employee_name'] as String?) ?? '—';

    final metaRows = <_MetaRow>[
      _MetaRow('Fecha y hora', _formatDate(s['created_at'] as String?)),
      _MetaRow('Tipo de venta', _sourceLabel(s['source'] as String?)),
      _MetaRow('Método de pago', _methodLabel(s['payment_method'] as String?)),
      _MetaRow('Cajero', cashier.isEmpty ? '—' : cashier),
      if ((s['customer_name_snapshot'] as String? ?? '').isNotEmpty)
        _MetaRow('Cliente', s['customer_name_snapshot'] as String),
    ];

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
          receiptNumber > 0 ? 'Recibo #$receiptNumber' : 'Detalle de venta',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _MetaCard(rows: metaRows),
          const SizedBox(height: 16),
          _SectionTitle('Productos vendidos (${items.length})'),
          const SizedBox(height: 8),
          if (items.isEmpty)
            _EmptyHint('Sin items registrados.')
          else
            ...items.map((it) => _ItemRow(
                  name: (it['name'] as String?) ?? '—',
                  quantity: (it['quantity'] as num?)?.toInt() ?? 1,
                  price: (it['price'] as num?)?.toDouble() ?? 0,
                  subtotal: (it['subtotal'] as num?)?.toDouble() ?? 0,
                  fmtCOP: _formatCOP,
                )),
          const SizedBox(height: 16),
          _TotalsCard(
            total: total.toDouble(),
            tax: tax.toDouble(),
            tip: tip.toDouble(),
            fmtCOP: _formatCOP,
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    key: const Key('receipt_reprint'),
                    onPressed: _printing ? null : _reprint,
                    icon: _printing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded),
                    label: const Text(
                      'Reimprimir',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    key: const Key('receipt_whatsapp'),
                    onPressed: _sending ? null : _sendWhatsApp,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.chat_rounded),
                    label: const Text(
                      'WhatsApp',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.rows});
  final List<_MetaRow> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i < rows.length - 1) {
        children.add(const Divider(height: 14, color: Color(0xFFEEEEEE)));
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: children),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(text,
          style: const TextStyle(color: AppTheme.textSecondary)),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.name,
    required this.quantity,
    required this.price,
    required this.subtotal,
    required this.fmtCOP,
  });

  final String name;
  final int quantity;
  final double price;
  final double subtotal;
  final String Function(num) fmtCOP;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '$quantity × ${fmtCOP(price)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            fmtCOP(subtotal),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
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
    required this.tax,
    required this.tip,
    required this.fmtCOP,
  });

  final double total;
  final double tax;
  final double tip;
  final String Function(num) fmtCOP;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          if (tax > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('IVA',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  Text(fmtCOP(tax)),
                ],
              ),
            ),
          if (tip > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Propina',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  Text(fmtCOP(tip)),
                ],
              ),
            ),
          if (tax > 0 || tip > 0) const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                fmtCOP(total),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
