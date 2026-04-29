import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' hide LinearGradient;
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../dashboard/main_dashboard_screen.dart';

/// Splash screen animado con Rive (o fallback Flutter mientras no haya .riv).
///
/// Lógica de autenticación:
///   - Verifica JWT en secure storage mientras corre la animación.
///   - Token válido  → DashboardScreen
///   - Sin sesión    → LoginScreen
///
/// Para activar Rive: coloca el archivo en `assets/rive/vendia_splash.riv`.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  static const _riveAssetPath = 'assets/rive/vendia_splash.riv';
  static const _minSplashDuration = Duration(milliseconds: 3000);

  bool _riveAvailable = false;

  // ── Controladores de animación ────────────────────────────────────────────
  /// Entrada: logo + texto aparecen (forward una sola vez)
  late final AnimationController _entranceCtrl;

  /// Pulso idle del logo (loop)
  late final AnimationController _pulseCtrl;

  /// Nodos de red neuronal (loop lento)
  late final AnimationController _nodesCtrl;

  // Tweens de entrada
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    // Entrada (1.4 s)
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );

    // Pulso idle (0.95 s, loop)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);

    // Nodos (4 s, loop)
    _nodesCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    // Verificar asset Rive y lanzar auth check en paralelo
    _checkRiveAsset();
    _init();

    // Arrancar la animación de entrada
    _entranceCtrl.forward();
  }

  Future<void> _checkRiveAsset() async {
    try {
      await rootBundle.load(_riveAssetPath);
      if (mounted) setState(() => _riveAvailable = true);
    } catch (_) {}
  }

  Future<void> _init() async {
    final stopwatch = Stopwatch()..start();

    final auth = AuthService();
    final hasSession = await auth.hasSession();
    String ownerName = '';
    String businessName = '';

    if (hasSession) {
      ownerName = await auth.getOwnerName() ?? '';
      businessName = await auth.getBusinessName() ?? '';
    }

    final elapsed = stopwatch.elapsed;
    if (elapsed < _minSplashDuration) {
      await Future.delayed(_minSplashDuration - elapsed);
    }

    if (!mounted) return;
    _navigate(
        hasSession: hasSession,
        ownerName: ownerName,
        businessName: businessName);
  }

  void _navigate({
    required bool hasSession,
    required String ownerName,
    required String businessName,
  }) {
    final route = hasSession
        ? PageRouteBuilder(
            pageBuilder: (_, animation, __) => const MainDashboardScreen(),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(
              opacity:
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 500),
          )
        : MaterialPageRoute(builder: (_) => const LoginScreen());

    Navigator.of(context).pushReplacement(route);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _nodesCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: _riveAvailable ? _buildRive() : _buildFallback(),
    );
  }

  Widget _buildRive() {
    return RiveAnimation.asset(
      _riveAssetPath,
      fit: BoxFit.cover,
      onInit: (_) {},
    );
  }

  Widget _buildFallback() {
    return Stack(
      children: [
        // ── Fondo: nodos de red neuronal ──────────────────────────────────
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _nodesCtrl,
            builder: (_, __) => CustomPaint(
              painter: _NeuralNetworkPainter(progress: _nodesCtrl.value),
            ),
          ),
        ),

        // ── Contenido central ─────────────────────────────────────────────
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_entranceCtrl, _pulseCtrl]),
            builder: (_, __) {
              final pulse = 1.0 + (_pulseCtrl.value * 0.025);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Transform.scale(
                        scale: pulse,
                        child: const _VendiaLogo(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Texto
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          const Text(
                            'VendIA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Su tienda, inteligente',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 20,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Logo widget ───────────────────────────────────────────────────────────────

/// Logo placeholder de VendIA: "V" estilizada con degradado y brillo.
/// Reemplazar por el asset real cuando esté disponible.
class _VendiaLogo extends StatelessWidget {
  const _VendiaLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A6AE8), Color(0xFF1D33B1)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFF1D33B1).withValues(alpha: 0.6),
            blurRadius: 40,
            spreadRadius: 8,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Brillo interior (top-left)
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          // "V" con punto IA
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'V',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 58,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  letterSpacing: -2,
                ),
              ),
              // Tres nodos pequeños debajo de la "V" — alusión a IA
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == 1 ? 7 : 5,
                    height: i == 1 ? 7 : 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: i == 1 ? 1.0 : 0.6),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── CustomPainter: red neuronal de fondo ──────────────────────────────────────

class _NeuralNetworkPainter extends CustomPainter {
  final double progress;

  _NeuralNetworkPainter({required this.progress});

  // Posiciones relativas de los nodos (0.0–1.0 del canvas)
  static const _nodes = [
    Offset(0.12, 0.18),
    Offset(0.82, 0.14),
    Offset(0.25, 0.42),
    Offset(0.72, 0.38),
    Offset(0.10, 0.68),
    Offset(0.88, 0.62),
    Offset(0.40, 0.80),
    Offset(0.65, 0.82),
    Offset(0.50, 0.22),
    Offset(0.50, 0.58),
  ];

  // Pares de nodos conectados
  static const _edges = [
    [0, 2],
    [0, 8],
    [1, 3],
    [1, 8],
    [2, 9],
    [3, 9],
    [4, 6],
    [5, 7],
    [6, 9],
    [7, 9],
    [2, 4],
    [3, 5],
    [8, 9],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final positions = _nodes
        .map((n) => Offset(n.dx * size.width, n.dy * size.height))
        .toList();

    // ── Conexiones ──────────────────────────────────────────────────────────
    for (final edge in _edges) {
      final a = positions[edge[0]];
      final b = positions[edge[1]];

      // Cada arista tiene su propio ritmo de parpadeo
      final phase = (edge[0] * 0.13 + edge[1] * 0.07);
      final alpha = (0.5 + 0.5 * math.sin((progress + phase) * math.pi * 2))
          .clamp(0.0, 1.0);

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.18)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(a, b, paint);
    }

    // ── Nodos ───────────────────────────────────────────────────────────────
    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final phase = i * 0.1;
      final pulse = 0.5 + 0.5 * math.sin((progress + phase) * math.pi * 2);

      // Halo exterior
      final haloPaint = Paint()
        ..color = Colors.white.withValues(alpha: pulse * 0.10)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 10.0, haloPaint);

      // Núcleo del nodo
      final nodePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15 + pulse * 0.20)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 4.5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(_NeuralNetworkPainter old) => old.progress != progress;
}
