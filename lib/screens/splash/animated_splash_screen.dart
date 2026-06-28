import 'dart:async';
import 'dart:math';
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
  // Tope de seguridad: si la animación no termina (assets que no cargan), entrar.
  static const _maxSplashDuration = Duration(seconds: 7);

  late final List<String> _logos;
  bool _animDone = false;
  bool _authResolved = false;
  bool _navigated = false;
  bool _hasSession = false;
  String _ownerName = '';
  String _businessName = '';
  Timer? _safeguard;

  @override
  void initState() {
    super.initState();
    // VendIA constante + 1 logo al azar (distinto cada apertura).
    final other = SplashAssets.randomOther(Random());
    _logos = [SplashAssets.vendia, other];
    _resolveAuth();
    // Salvaguarda: si los assets no cargan (web lento/roto), entrar igual.
    _safeguard = Timer(_maxSplashDuration, () {
      _animDone = true;
      _maybeGo();
    });
  }

  @override
  void dispose() {
    _safeguard?.cancel();
    super.dispose();
  }

  Future<void> _resolveAuth() async {
    final auth = AuthService();
    final has = await auth.hasSession();
    if (has) {
      _ownerName = await auth.getOwnerName() ?? '';
      _businessName = await auth.getBusinessName() ?? '';
    }
    _hasSession = has;
    _authResolved = true;
    _maybeGo();
  }

  // Navega cuando la animación TERMINÓ (esperó la carga) y la auth está lista.
  void _onAnimDone() {
    _animDone = true;
    _maybeGo();
  }

  void _maybeGo() {
    if (_navigated || !_animDone || !_authResolved || !mounted) return;
    _navigated = true;
    _navigate(
        hasSession: _hasSession,
        ownerName: _ownerName,
        businessName: _businessName);
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
                  draw: const Duration(milliseconds: 750),
                  hold: const Duration(milliseconds: 300),
                  erase: const Duration(milliseconds: 350),
                  overlap: const Duration(milliseconds: 150),
                  onDone: _onAnimDone,
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
