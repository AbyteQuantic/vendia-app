import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import 'pos_controller.dart';

class CartSheet extends StatelessWidget {
  const CartSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PosController>(
      builder: (context, ctrl, _) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Título
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Carrito (${ctrl.cartCount})',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        TextButton(
                          onPressed:
                              ctrl.cart.isNotEmpty ? ctrl.clearCart : null,
                          child: const Text(
                            'Vaciar',
                            style:
                                TextStyle(color: AppTheme.error, fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Items del carrito
                  Expanded(
                    child: ctrl.cart.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shopping_cart_outlined,
                                    size: 64, color: AppTheme.textSecondary),
                                SizedBox(height: 12),
                                Text(
                                  'El carrito está vacío',
                                  style: TextStyle(
                                      fontSize: 18,
                                      color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 8),
                            itemCount: ctrl.cart.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final item = ctrl.cart[i];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.product.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item.product.formattedPrice,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Controles de cantidad — botones GRANDES
                                    Row(
                                      children: [
                                        _QtyButton(
                                          icon: Icons.remove,
                                          onTap: () => ctrl.decreaseQuantity(
                                              item.product.id),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          width: 40,
                                          child: Text(
                                            '${item.quantity}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        _QtyButton(
                                          icon: Icons.add,
                                          onTap: () =>
                                              ctrl.addToCart(item.product),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(width: 12),
                                    // Subtotal
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        item.formattedSubtotal,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // ── Panel de pago ─────────────────────────────────────────
                  _PaymentPanel(ctrl: ctrl),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: icon == Icons.add ? 'Aumentar cantidad' : 'Disminuir cantidad',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Icon(icon, size: 28, color: AppTheme.primary),
        ),
      ),
    );
  }
}

// ── Panel inferior de pago ─────────────────────────────────────────────────────

class _PaymentPanel extends StatefulWidget {
  final PosController ctrl;
  const _PaymentPanel({required this.ctrl});

  @override
  State<_PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<_PaymentPanel> {
  String _paymentMethod = 'cash';

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final isProcessing = ctrl.status == PosStatus.processingPayment;

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total a cobrar',
                  style:
                      TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
              Text(
                ctrl.formattedTotal,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Método de pago — 3 botones táctiles grandes
          Row(
            children: [
              _PayMethodChip(
                label: 'Efectivo',
                icon: Icons.payments_rounded,
                selected: _paymentMethod == 'cash',
                onTap: () => setState(() => _paymentMethod = 'cash'),
              ),
              const SizedBox(width: 8),
              _PayMethodChip(
                label: 'Transferencia',
                icon: Icons.phone_android_rounded,
                selected: _paymentMethod == 'transfer',
                onTap: () => setState(() => _paymentMethod = 'transfer'),
              ),
              const SizedBox(width: 8),
              _PayMethodChip(
                label: 'Tarjeta',
                icon: Icons.credit_card_rounded,
                selected: _paymentMethod == 'card',
                onTap: () => setState(() => _paymentMethod = 'card'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Botón cobrar
          ElevatedButton.icon(
            onPressed: isProcessing || ctrl.cart.isEmpty
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    final ok = await ctrl.processSale(_paymentMethod);
                    if (!context.mounted) return;
                    if (ok) {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Colors.white, size: 24),
                              SizedBox(width: 12),
                              Text('¡Venta registrada!',
                                  style: TextStyle(fontSize: 20)),
                            ],
                          ),
                          backgroundColor: AppTheme.success,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    } else {
                      HapticFeedback.heavyImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.error_rounded,
                                  color: Colors.white, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(ctrl.errorMessage,
                                    style: const TextStyle(fontSize: 18)),
                              ),
                            ],
                          ),
                          backgroundColor: AppTheme.error,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },
            icon: isProcessing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Icon(Icons.check_circle_rounded, size: 26),
            label: Text(
                isProcessing ? 'Procesando...' : 'Cobrar y registrar venta'),
          ),
        ],
      ),
    );
  }
}

class _PayMethodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PayMethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
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
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.borderColor,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                    size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
