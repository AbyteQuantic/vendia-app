import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../database/collections/local_customer.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import 'fiar_controller.dart';
import 'widgets/payment_dialog.dart';

class CreditDetailScreen extends StatefulWidget {
  final LocalCustomer customer;
  final FiarController ctrl;

  const CreditDetailScreen({
    super.key,
    required this.customer,
    required this.ctrl,
  });

  @override
  State<CreditDetailScreen> createState() => _CreditDetailScreenState();
}

class _CreditDetailScreenState extends State<CreditDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.loadCreditsForCustomer(widget.customer.uuid);
  }

  Future<void> _registerPayment(String creditUuid, double maxAmount) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PaymentDialog(
        maxAmount: maxAmount,
        customerName: widget.customer.name,
      ),
    );

    if (result == null) return;

    await widget.ctrl.registerPayment(
      creditUuid: creditUuid,
      amount: result['amount'] as double,
      note: result['note'] as String? ?? '',
    );

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text('Abono de ${formatCOP(result['amount'] as double)} registrado',
                style: const TextStyle(fontSize: 18)),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          widget.customer.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Detalle de deuda de ${widget.customer.name}',
        child: ListenableBuilder(
          listenable: widget.ctrl,
          builder: (context, _) {
            final credits = widget.ctrl.credits;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppTheme.error.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Text('Saldo pendiente',
                          style: TextStyle(
                              fontSize: 18, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        formatCOP(widget.customer.balance),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total fiado: ${formatCOP(widget.customer.totalCredit)} · '
                        'Pagado: ${formatCOP(widget.customer.totalPaid)}',
                        style: const TextStyle(
                            fontSize: 18, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text('Historial de ventas fiadas',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 12),

                if (credits.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text('Sin registros de fiado',
                          style: TextStyle(
                              fontSize: 18, color: AppTheme.textSecondary)),
                    ),
                  )
                else
                  ...credits.map((credit) {
                    final isPaid = credit.status == 'paid';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatCOP(credit.totalAmount),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPaid
                                      ? AppTheme.success.withValues(alpha: 0.1)
                                      : AppTheme.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  isPaid ? 'Pagado' : 'Pendiente',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isPaid
                                        ? AppTheme.success
                                        : AppTheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Abonado: ${formatCOP(credit.paidAmount)} · '
                            'Resta: ${formatCOP(credit.balance)}',
                            style: const TextStyle(
                                fontSize: 18, color: AppTheme.textSecondary),
                          ),

                          // Payments history
                          if (credit.payments.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...credit.payments.map((p) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outlined,
                                          size: 18, color: AppTheme.success),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${formatCOP(p.amount)} — ${_formatDate(p.paidAt)}',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                )),
                          ],

                          if (!isPaid) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton.icon(
                                onPressed: () => _registerPayment(
                                    credit.uuid, credit.balance),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.success,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                ),
                                icon: const Icon(Icons.payments_rounded,
                                    size: 22, color: Colors.white),
                                label: const Text('Registrar abono',
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.white)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final d = date;
    return '${d.day}/${d.month}/${d.year}';
  }
}
