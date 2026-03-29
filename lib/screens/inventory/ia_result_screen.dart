import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import 'price_pending_screen.dart';

/// Shows the products detected by AI from the supplier invoice.
class IaResultScreen extends StatelessWidget {
  const IaResultScreen({super.key});

  // Mock detected products
  static final List<_DetectedProduct> _mockProducts = [
    _DetectedProduct(
      emoji: '\uD83E\uDD64', // cup with straw
      name: 'Coca-Cola 350ml',
      unitPrice: 1500,
      quantity: 24,
    ),
    _DetectedProduct(
      emoji: '\uD83E\uDDC3', // beverage box
      name: 'Hit Naranja 1L',
      unitPrice: 3200,
      quantity: 12,
    ),
    _DetectedProduct(
      emoji: '\uD83D\uDCA7', // droplet
      name: 'Agua Cristal 600ml',
      unitPrice: 1000,
      quantity: 48,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final totalInvoice = _mockProducts.fold<double>(
      0,
      (sum, p) => sum + p.unitPrice * p.quantity,
    );
    final count = _mockProducts.length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Resultados de la lectura de factura',
        child: Column(
          children: [
            // Green header
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 24,
                right: 24,
                bottom: 28,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    Semantics(
                      button: true,
                      label: 'Volver',
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 26),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'IA detecto $count productos',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Factura de Postobon',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Product list
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                itemCount: _mockProducts.length,
                itemBuilder: (context, index) {
                  final p = _mockProducts[index];
                  final total = p.unitPrice * p.quantity;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppTheme.borderColor, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        // Emoji avatar
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0x20667EEA),
                                Color(0x20764BA2),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              p.emoji,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${formatCOP(p.unitPrice)} x ${p.quantity} = ${formatCOP(total)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Green check
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0x2010B981),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Color(0xFF10B981), size: 24),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Total bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0x1010B981),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0x3010B981), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total factura',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    formatCOP(totalInvoice),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const PricePendingScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_rounded,
                        size: 24, color: Colors.white),
                    label: const Text(
                      'Confirmar y Guardar',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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
}

class _DetectedProduct {
  final String emoji;
  final String name;
  final double unitPrice;
  final int quantity;

  const _DetectedProduct({
    required this.emoji,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });
}
