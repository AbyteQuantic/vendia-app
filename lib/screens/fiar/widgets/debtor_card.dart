import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../database/collections/local_customer.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/format_cop.dart';

class DebtorCard extends StatelessWidget {
  final LocalCustomer customer;
  final VoidCallback onTap;
  final VoidCallback onWhatsApp;

  const DebtorCard({
    super.key,
    required this.customer,
    required this.onTap,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final balance = customer.balance;
    final hasDebt = balance > 0;

    return Semantics(
      button: true,
      label: '${customer.name}, saldo pendiente ${formatCOP(balance)}',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (customer.phone.isNotEmpty)
                          Text(
                            customer.phone,
                            style: const TextStyle(
                              fontSize: 18,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    formatCOP(balance),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: hasDebt ? AppTheme.error : AppTheme.success,
                    ),
                  ),
                ],
              ),
              if (hasDebt) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.payments_rounded,
                        label: 'Abonar',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9668), Color(0xFF10B981)],
                        ),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onTap();
                        },
                      ),
                    ),
                    if (customer.phone.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.chat_rounded,
                          label: 'Recordar',
                          color: const Color(0xFF25D366),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            onWhatsApp();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.color,
    this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: gradient == null ? color : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
