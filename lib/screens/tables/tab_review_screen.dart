import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_table_tab.dart';
import '../../utils/currency_input.dart';
import '../pos/cart_controller.dart';

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
    this.onItemRemoved,
  });

  final String sessionToken;
  final String tableLabel;
  // Needed for the "Registrar Abono Manual" authenticated POST.
  // Null disables the button — the cashier can still read the
  // cuenta but can't add abonos until the cart has synced.
  final String? orderId;

  /// Called when an item is successfully removed from the tab.
  /// The POS screen uses this to restore stock reactively.
  final void Function(String productUuid, int quantity)? onItemRemoved;

  @override
  State<TabReviewScreen> createState() => _TabReviewScreenState();
}

class _TabReviewScreenState extends State<TabReviewScreen> {
  late final ApiService _api;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _errorMessage;
  bool _closedHandled = false;

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

    // Read the authoritative pendingBalance from the ISAR stream first.
    // _data only updates when _load() runs, which can lag right after
    // an abono — the stream reflects commitOrderToTab / applyServerTabSnapshot
    // immediately. Fall back to _data, then to 0.
    double prefillRemaining = 0;
    try {
      final tab = await DatabaseService.instance
          .watchTableTabByLabel(widget.tableLabel)
          .first;
      if (tab != null && tab.pendingBalance > 0) {
        prefillRemaining = tab.pendingBalance;
      }
    } on StateError catch (_) {
      // ISAR not initialized in tests — fine
    }
    if (prefillRemaining <= 0) {
      prefillRemaining =
          (_data?['remaining_balance'] as num?)?.toDouble() ?? 0;
    }
    if (!mounted) return;

    final result = await showModalBottomSheet<_AbonoResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final methods = (_data?['payment_methods'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        return _ManualAbonoSheet(
          remaining: prefillRemaining,
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

      // Optimistic update: reflect the abono on the local stream
      // immediately. Backend reconciliation (via _load) will overwrite
      // with authoritative value if it differs.
      try {
        final currentTab = await DatabaseService.instance
            .watchTableTabByLabel(widget.tableLabel)
            .first;
        final newAbonos = (currentTab?.abonosTotal ?? 0) + result.amount;
        await DatabaseService.instance.applyServerTabSnapshot({
          'label': widget.tableLabel,
          'abonos_total': newAbonos,
        });
      } on StateError catch (_) {
        // ISAR not initialized in tests — fine
      }

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

  Future<bool> _confirmRemoveItem({
    required String itemId,
    required String name,
    required String productUuid,
    required int quantity,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Quitar "$name" de la cuenta? El stock será devuelto.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || widget.orderId == null) return false;

    try {
      await _api.removeItemFromTab(widget.orderId!, itemId);
      if (!mounted) return false;
      HapticFeedback.mediumImpact();
      // Notify parent to restore stock reactively
      if (widget.onItemRemoved != null && productUuid.isNotEmpty) {
        widget.onItemRemoved!(productUuid, quantity);
      }
      await _load();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
      return false;
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
                          style: const TextStyle(
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
      body: StreamBuilder<LocalTableTab?>(
        stream: DatabaseService.instance
            .watchTableTabByLabel(widget.tableLabel),
        builder: (ctx, snap) {
          final tab = snap.data;
          final closed = tab != null &&
              (tab.status == 'completed' || tab.status == 'paid');
          if (closed && !_closedHandled) {
            _closedHandled = true;
            // Defer until after this build completes — can't pop inside builder.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Best-effort: tell the backend (idempotent server-side).
              if (widget.orderId != null) {
                _api
                    .closeOrder(widget.orderId!, 'multi')
                    .catchError((_) => <String, dynamic>{});
              }
              // Release the mesa bubble in the POS header.
              try {
                // ignore: use_build_context_synchronously
                ctx.read<CartController>().clearContextForLabel(widget.tableLabel);
              } catch (_) {}
              // Pop with a green confirmation.
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('¡Cuenta Pagada y Cerrada!'),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 3),
                ),
              );
              Navigator.of(ctx).maybePop();
            });
            // Show legacy/empty content until the pop fires.
            return _buildLegacyContent();
          }
          if (tab != null) return _buildReactiveContent(tab);
          return _buildLegacyContent();
        },
      ),
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

  Widget _buildReactiveContent(LocalTableTab tab) {
    final items = tab.items;
    final abonos = (_data?['partial_payments'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final total = tab.grossTotal;
    final paid = tab.abonosTotal;
    final remaining = tab.pendingBalance;

    // Build server itemIds by productUuid in arrival order to match local items
    final serverItems = (_data?['items'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    // Group server itemIds by productUuid in arrival order, so the
    // Nth local row with uuid X maps to the Nth server item with uuid X.
    final serverIdsByUuid = <String, List<String>>{};
    for (final s in serverItems) {
      final u = (s['product_uuid'] as String?) ?? '';
      final id = (s['id'] as String?) ?? '';
      if (u.isEmpty || id.isEmpty) continue;
      (serverIdsByUuid[u] ??= []).add(id);
    }

    final status = tab.status;
    final isOpen = status == 'nuevo' ||
        status == 'preparando' ||
        status == 'listo' ||
        status.isEmpty;
    final canDeleteRows = isOpen && widget.orderId != null;

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
            ...items.asMap().entries.map((e) {
              final i = e.key;
              final it = e.value;
              // 0-based occurrence of this item among uuid siblings earlier in the list.
              final occurrence = items
                  .take(i)
                  .where((p) => p.productUuid == it.productUuid)
                  .length;
              final candidates = serverIdsByUuid[it.productUuid] ?? const [];
              final serverItemId =
                  occurrence < candidates.length ? candidates[occurrence] : '';

              final keyStr =
                  '$i|${it.productUuid}|${it.sentAt?.toIso8601String() ?? ''}';
              return _ItemRow(
                key: ValueKey(keyStr),
                name: it.productName,
                quantity: it.quantity,
                unitPrice: it.unitPrice,
                subtotal: it.quantity * it.unitPrice,
                emoji: '',
                time: _fmtTime(it.sentAt?.toIso8601String()),
                fmtCOP: _fmtCOP,
                canDelete: canDeleteRows && serverItemId.isNotEmpty,
                onDelete: (canDeleteRows && serverItemId.isNotEmpty)
                    ? () async {
                        final removed = await _confirmRemoveItem(
                          itemId: serverItemId,
                          productUuid: it.productUuid,
                          name: it.productName,
                          quantity: it.quantity,
                        );
                        if (removed) {
                          try {
                            await DatabaseService.instance.removeTabItem(
                              label: widget.tableLabel,
                              productUuid: it.productUuid,
                              occurrence: occurrence,
                            );
                          } on StateError catch (_) {}
                        }
                      }
                    : null,
              );
            }),
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

  Widget _buildLegacyContent() {
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
    // Business rule: delete only allowed on open accounts
    final status = (data['status'] as String?) ?? '';
    final isOpen = status.isEmpty ||
        status == 'nuevo' ||
        status == 'preparando' ||
        status == 'listo';
    final canDelete = isOpen && widget.orderId != null;

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
            ...items.asMap().entries.map((e) {
              final i = e.key;
              final it = e.value;
              final itemId = (it['id'] as String?) ?? '';
              final keyStr =
                  itemId.isNotEmpty ? itemId : '$i|${it.hashCode}';
              return _ItemRow(
                key: ValueKey(keyStr),
                name: (it['product_name'] as String?) ?? '—',
                quantity: (it['quantity'] as num?)?.toInt() ?? 1,
                unitPrice: (it['unit_price'] as num?)?.toDouble() ?? 0,
                subtotal: (it['subtotal'] as num?)?.toDouble() ?? 0,
                emoji: (it['emoji'] as String?) ?? '',
                time: _fmtTime(it['added_at'] as String?),
                fmtCOP: _fmtCOP,
                canDelete: canDelete && itemId.isNotEmpty,
                onDelete: canDelete && itemId.isNotEmpty
                    ? () => _confirmRemoveItem(
                          itemId: itemId,
                          name: (it['product_name'] as String?) ?? '',
                          productUuid: (it['product_uuid'] as String?) ?? '',
                          quantity: (it['quantity'] as num?)?.toInt() ?? 1,
                        )
                    : null,
              );
            }),
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
    super.key,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.emoji,
    required this.time,
    required this.fmtCOP,
    this.canDelete = false,
    this.onDelete,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final String emoji;
  final String time;
  final String Function(num) fmtCOP;
  final bool canDelete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(14, 14, canDelete ? 6 : 14, 14),
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
          if (canDelete) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Eliminar producto',
              icon: const Icon(Icons.delete_rounded,
                  color: AppTheme.error, size: 22),
              onPressed: onDelete,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
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
          const Icon(Icons.check_circle_rounded,
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
            style: const TextStyle(
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
      text: CurrencyUtils.formatInt(widget.remaining.round()),
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
    final amount = CurrencyUtils.parseToDouble(_amountCtrl.text);
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
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: '\$ ',
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
