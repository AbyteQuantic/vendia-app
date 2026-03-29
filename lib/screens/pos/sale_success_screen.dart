import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

class SaleSuccessScreen extends StatefulWidget {
  final String total;
  final String paymentMethod;

  const SaleSuccessScreen({
    super.key,
    required this.total,
    required this.paymentMethod,
  });

  @override
  State<SaleSuccessScreen> createState() => _SaleSuccessScreenState();
}

class _SaleSuccessScreenState extends State<SaleSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _methodLabel => switch (widget.paymentMethod) {
        'transfer' => 'Transferencia',
        'card' => 'Tarjeta',
        'credit' => 'Fiado',
        _ => 'Efectivo',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Venta registrada exitosamente por ${widget.total}',
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // Check icon with confetti dots
                SizedBox(
                  width: 200,
                  height: 200,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Confetti dots scattered around the check
                        ..._buildConfettiDots(),
                        // Main check circle
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.success,
                            size: 80,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      const Text(
                        '!Venta registrada!',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.total,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pago con $_methodLabel',
                        style: const TextStyle(
                          fontSize: 20,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                // Button 1: Nueva venta (green gradient, 64px)
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D9668), Color(0xFF10B981)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(true);
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_cart_rounded,
                                size: 28, color: Colors.white),
                            SizedBox(width: 12),
                            Text(
                              'Nueva venta',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Button 2: Imprimir Recibo (blue/grey outline, 56px)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Imprimiendo recibo...'),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppTheme.textSecondary, width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.print_rounded,
                        size: 24, color: AppTheme.textSecondary),
                    label: const Text(
                      'Imprimir Recibo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Button 3: Enviar por WhatsApp (#25D366, 56px)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enviando recibo por WhatsApp...'),
                            ),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_rounded,
                                size: 24, color: Colors.white),
                            SizedBox(width: 12),
                            Text(
                              'Enviar por WhatsApp',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildConfettiDots() {
    final random = Random(42); // Fixed seed for consistent layout
    const confettiColors = [
      Color(0xFF0D9668),
      Color(0xFF3D5AFE),
      Color(0xFFF59E0B),
      Color(0xFFDC2626),
      Color(0xFF7C3AED),
      Color(0xFF25D366),
      Color(0xFFEC4899),
    ];

    final dots = <Widget>[];
    for (var i = 0; i < 18; i++) {
      final color = confettiColors[i % confettiColors.length];
      final isRect = i % 3 == 0;
      final size = 6.0 + random.nextDouble() * 8;
      // Position in a ring around center (100,100) with radius 70-95
      final angle = (i / 18) * 2 * pi + random.nextDouble() * 0.4;
      final radius = 70.0 + random.nextDouble() * 25;
      final x = 100 + cos(angle) * radius - size / 2;
      final y = 100 + sin(angle) * radius - size / 2;

      dots.add(
        Positioned(
          left: x,
          top: y,
          child: Transform.rotate(
            angle: random.nextDouble() * pi,
            child: Container(
              width: size,
              height: isRect ? size * 1.8 : size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7 + random.nextDouble() * 0.3),
                borderRadius: BorderRadius.circular(isRect ? 2 : size / 2),
              ),
            ),
          ),
        ),
      );
    }
    return dots;
  }
}
