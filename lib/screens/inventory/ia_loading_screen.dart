import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'ia_result_screen.dart';

/// IA Loading Screen — shows a breathing logo + animated dots
/// while the AI "processes" the supplier invoice.
class IaLoadingScreen extends StatefulWidget {
  final String imagePath;

  const IaLoadingScreen({super.key, required this.imagePath});

  @override
  State<IaLoadingScreen> createState() => _IaLoadingScreenState();
}

class _IaLoadingScreenState extends State<IaLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _dotsCtrl;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the logo (1.0 -> 1.05 -> 1.0)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Dots bouncing animation
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Call real AI endpoint
    _scanInvoice();
  }

  Future<void> _scanInvoice() async {
    try {
      final file = File(widget.imagePath);

      // Safety net: verify file size before sending
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La imagen es demasiado pesada. Intente de nuevo con mejor luz.',
              style: TextStyle(fontSize: 16),
            ),
            backgroundColor: AppTheme.warning,
          ),
        );
        Navigator.of(context).pop();
        return;
      }

      final api = ApiService(AuthService());
      final result = await api.scanInvoice(file);
      if (!mounted) return;
      HapticFeedback.mediumImpact();

      final products = (result['products'] as List?)
              ?.map((p) => p as Map<String, dynamic>)
              .toList() ??
          [];
      final provider = result['provider'] as String? ?? 'Proveedor';

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => IaResultScreen(
            extractedProducts: products,
            providerName: provider,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al leer factura: $e',
              style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Semantics(
        label: 'Procesando factura con inteligencia artificial',
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Breathing VendIA logo
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(40),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x20667EEA),
                            Color(0x20764BA2),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'V',
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Animated bouncing dots
                  AnimatedBuilder(
                    animation: _dotsCtrl,
                    builder: (context, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          final delay = i * 0.2;
                          final value =
                              ((_dotsCtrl.value - delay) % 1.0).clamp(0.0, 1.0);
                          final offset =
                              -8.0 * math.sin(value * math.pi);
                          return Transform.translate(
                            offset: Offset(0, offset),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF667EEA)
                                    .withValues(alpha: 0.4 + 0.6 * math.sin(value * math.pi)),
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'Leyendo productos y precios...',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  const Text(
                    'Esto toma unos segundos',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  // AI badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0x10667EEA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '\u2728 Inteligencia Artificial VendIA',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF667EEA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
