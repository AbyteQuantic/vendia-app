import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/splash/logo_reveal.dart';
import '../../widgets/vendia_logo.dart';
import '../auth/login_screen.dart';
import '../onboarding/post_login_gate.dart';

/// Splash de arranque (Spec 087): el logo se "dibuja" siguiendo el trazo y se
/// revela completo. VendIA es la constante + 1 logo al azar cada apertura.
///
/// Lógica de autenticación (sin cambios):
///   - Verifica JWT en secure storage mientras corre la animación.
///   - Token válido → PostLoginGate · Sin sesión → LoginScreen
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> {
  // Piso del splash = lo que dura el dibujado de VendIA + 1 logo (~2.4s), así
  // se alcanza a ver el efecto antes de navegar.
  static const _minSplashDuration = Duration(milliseconds: kIsWeb ? 2400 : 2600);

  late final List<String> _logos;

  @override
  void initState() {
    super.initState();
    // VendIA constante + 1 logo al azar (distinto cada apertura).
    final other = SplashAssets.randomOther(Random());
    _logos = [SplashAssets.vendia, other];
    _init();
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
            pageBuilder: (_, animation, __) => PostLoginGate(
              ownerName: ownerName,
              businessName: businessName,
            ),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                height: 300,
                child: LogoSequenceReveal(
                  logos: _logos,
                  draw: const Duration(milliseconds: 700),
                  hold: const Duration(milliseconds: 250),
                  erase: const Duration(milliseconds: 300),
                  overlap: const Duration(milliseconds: 150),
                ),
              ),
              const SizedBox(height: 16),
              const VendiaWordmark(fontSize: 40, baseColor: AppTheme.primaryDark),
              const SizedBox(height: 8),
              const Text(
                'Su tienda, inteligente',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 18,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
