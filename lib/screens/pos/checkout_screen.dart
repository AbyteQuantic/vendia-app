import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/cart_item.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver al carrito',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Confirmar Venta',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Pantalla de confirmación de venta',
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'Resumen de la venta',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Item list
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
                                  horizontal: 20, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.items[i].product.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${widget.items[i].quantity} × ${widget.items[i].product.formattedPrice}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    widget.items[i].formattedSubtotal,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (i < widget.items.length - 1)
                              const Divider(
                                  height: 1, indent: 20, endIndent: 20),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            widget.formattedTotal,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    const Text(
                      'Método de pago',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _PaymentMethodButton(
                      icon: Icons.payments_rounded,
                      label: 'Efectivo',
                      selected: _selectedMethod == 'cash',
                      onTap: () => setState(() => _selectedMethod = 'cash'),
                    ),
                    const SizedBox(height: 12),
                    _PaymentMethodButton(
                      icon: Icons.phone_android_rounded,
                      label: 'Transferencia',
                      selected: _selectedMethod == 'transfer',
                      onTap: () => setState(() => _selectedMethod = 'transfer'),
                    ),
                    const SizedBox(height: 12),
                    _PaymentMethodButton(
                      icon: Icons.credit_card_rounded,
                      label: 'Tarjeta',
                      selected: _selectedMethod == 'card',
                      onTap: () => setState(() => _selectedMethod = 'card'),
                    ),
                    const SizedBox(height: 12),
                    _PaymentMethodButton(
                      icon: Icons.menu_book_rounded,
                      label: 'Fiar',
                      selected: _selectedMethod == 'credit',
                      onTap: () => setState(() => _selectedMethod = 'credit'),
                      accentColor: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ),

              // Confirm button
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _confirmSale,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded,
                            size: 28, color: Colors.white),
                        label: Text(
                          'Registrar venta por ${widget.formattedTotal}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSale() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          '¿Registrar esta venta?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Total: ${widget.formattedTotal}',
          style: const TextStyle(fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(
                CheckoutResult(confirmed: true, paymentMethod: _selectedMethod),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              minimumSize: const Size(120, 56),
            ),
            child: const Text('Confirmar',
                style: TextStyle(fontSize: 20, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accentColor;

  const _PaymentMethodButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppTheme.primary;
    return Semantics(
      button: true,
      label: 'Método de pago: $label',
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.1) : AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : AppTheme.borderColor,
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? color : AppTheme.textSecondary, size: 32),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? color : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
