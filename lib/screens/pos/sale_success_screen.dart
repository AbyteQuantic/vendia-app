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
    with TickerProviderStateMixin {
  // Main orchestrator
  late final AnimationController _mainCtrl;
  // Confetti falling
  late final AnimationController _confettiCtrl;
  // Pulse on primary button
  late final AnimationController _pulseCtrl;

  // Staggered animations
  late final Animation<double> _checkScale;
  late final Animation<double> _checkFade;
  late final Animation<double> _titleFade;
  late final Animation<double> _titleSlide;
  late final Animation<double> _totalFade;
  late final Animation<double> _totalSlide;
  late final Animation<double> _methodFade;
  late final Animation<double> _methodSlide;
  late final Animation<double> _buttonsFade;
  late final Animation<double> _confettiProgress;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();

    // Main timeline: 1.6s total
    _mainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // Confetti: slow fall over 3s
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Pulse: gentle breathing loop
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Phase A: Check circle (0-500ms)
    _checkScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0, 0.35, curve: Curves.elasticOut),
      ),
    );
    _checkFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0, 0.2, curve: Curves.easeIn),
      ),
    );

    // Phase B: Title (300-600ms)
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.2, 0.4, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.2, 0.4, curve: Curves.easeOut),
      ),
    );

    // Phase C: Total (450-750ms)
    _totalFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.32, 0.52, curve: Curves.easeOut),
      ),
    );
    _totalSlide = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.32, 0.52, curve: Curves.easeOut),
      ),
    );

    // Phase D: Payment method (600-900ms)
    _methodFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.42, 0.62, curve: Curves.easeOut),
      ),
    );
    _methodSlide = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.42, 0.62, curve: Curves.easeOut),
      ),
    );

    // Phase E: Buttons (800-1200ms)
    _buttonsFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.55, 0.8, curve: Curves.easeOut),
      ),
    );

    // Confetti fall progress
    _confettiProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _confettiCtrl, curve: Curves.easeOutQuad),
    );

    // Pulse: gentle scale 1.0 → 1.04 → 1.0
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Start sequence
    _mainCtrl.forward();
    _confettiCtrl.forward();

    // Start pulse after confetti settles
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) _pulseCtrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _confettiCtrl.dispose();
    _pulseCtrl.dispose();
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
      backgroundColor: const Color(0xFFFFFBF7),
      body: Semantics(
        label: 'Venta registrada exitosamente por ${widget.total}',
        child: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: Listenable.merge([_mainCtrl, _confettiCtrl, _pulseCtrl]),
            builder: (context, _) => Column(
              children: [
                const Spacer(flex: 2),

                // ── Confetti + Check ─────────────────────────────
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Animated confetti
                      ..._buildAnimatedConfetti(),
                      // Check circle
                      FadeTransition(
                        opacity: _checkFade,
                        child: ScaleTransition(
                          scale: _checkScale,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: AppTheme.success,
                              size: 80,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Title ────────────────────────────────────────
                Transform.translate(
                  offset: Offset(0, _titleSlide.value),
                  child: Opacity(
                    opacity: _titleFade.value,
                    child: const Text(
                      '!Venta registrada!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Total ────────────────────────────────────────
                Transform.translate(
                  offset: Offset(0, _totalSlide.value),
                  child: Opacity(
                    opacity: _totalFade.value,
                    child: Text(
                      widget.total,
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Payment method ───────────────────────────────
                Transform.translate(
                  offset: Offset(0, _methodSlide.value),
                  child: Opacity(
                    opacity: _methodFade.value,
                    child: Text(
                      'Pago con $_methodLabel',
                      style: const TextStyle(
                        fontSize: 20,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // ── Buttons ──────────────────────────────────────
                Opacity(
                  opacity: _buttonsFade.value,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        28, 0, 28, MediaQuery.of(context).padding.bottom + 24),
                    child: Column(
                      children: [
                        // Primary: Nueva venta (with pulse)
                        ScaleTransition(
                          scale: _pulseAnim,
                          child: SizedBox(
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
                                      Text('Nueva venta',
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Imprimir Recibo
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Imprimiendo recibo...')),
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
                            label: const Text('Imprimir Recibo',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // WhatsApp
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
                                        content: Text(
                                            'Enviando recibo por WhatsApp...')),
                                  );
                                },
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.chat_rounded,
                                        size: 24, color: Colors.white),
                                    SizedBox(width: 12),
                                    Text('Enviar por WhatsApp',
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Animated confetti particles ──────────────────────────────────────────

  List<Widget> _buildAnimatedConfetti() {
    final rng = Random(42);
    const colors = [
      Color(0xFF0D9668), Color(0xFF3D5AFE), Color(0xFFF59E0B),
      Color(0xFFDC2626), Color(0xFF7C3AED), Color(0xFF25D366),
      Color(0xFFEC4899),
    ];

    final particles = <Widget>[];
    for (var i = 0; i < 22; i++) {
      final color = colors[i % colors.length];
      final isRect = i % 3 == 0;
      final size = 5.0 + rng.nextDouble() * 7;

      // Start position: clustered near center-top of the circle
      final startAngle = (i / 22) * 2 * pi + rng.nextDouble() * 0.3;
      final startRadius = 15.0 + rng.nextDouble() * 20;
      final startX = 110 + cos(startAngle) * startRadius;
      final startY = 90 + sin(startAngle) * startRadius;

      // End position: scattered outward + falling down
      final endRadius = 70.0 + rng.nextDouble() * 30;
      final endX = 110 + cos(startAngle) * endRadius;
      final endY = startY + 40 + rng.nextDouble() * 60; // fall downward
      final rotation = rng.nextDouble() * pi * 2;

      final progress = _confettiProgress.value;
      final x = startX + (endX - startX) * progress;
      final y = startY + (endY - startY) * progress;
      // Fade out in the last 30%
      final opacity = progress > 0.7
          ? (1.0 - (progress - 0.7) / 0.3).clamp(0.0, 1.0)
          : progress < 0.1
              ? (progress / 0.1).clamp(0.0, 1.0)
              : 1.0;

      particles.add(
        Positioned(
          left: x - size / 2,
          top: y - size / 2,
          child: Opacity(
            opacity: opacity * (0.6 + rng.nextDouble() * 0.4),
            child: Transform.rotate(
              angle: rotation + progress * pi,
              child: Container(
                width: size,
                height: isRect ? size * 1.8 : size,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(isRect ? 2 : size / 2),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return particles;
  }
}
