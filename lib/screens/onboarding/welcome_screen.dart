// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// Welcome screen — reemplaza el `OnboardingWizardScreen` de 3 pasos
// (F036). Una sola pantalla con logo + mensaje corto + botón
// "Empezar". Tocar el botón:
//   1. PATCH /store/profile { onboarding_completed: true }
//   2. Marca el flag local en AuthService (offline-safe)
//   3. Llama onCompleted (navega al Dashboard)
//
// El descubrimiento de capacidades ya NO se hace en el onboarding;
// pasa a vivir en el reel del Dashboard.
//
// 2026-05-25 — UI modernizada con layout inspirado en mockups de
// referencia (file-manager style): gradient full-screen, emoji
// centrado en círculo con sombra, card glassmorphism con el mensaje
// y CTA pill grande. Mantiene azul brand + Gerontodiseño (texto
// ≥17pt, táctil ≥48dp, 360dp). Mismo flujo de PATCH y navegación.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
// AppTheme se quitó de los imports: la pantalla pasó a usar Colors
// directos (blanco sobre gradient) en vez de los tokens textPrimary/
// textSecondary del theme. Se mantienen los hex literales del gradient
// alineados con AppTheme.primary.

class WelcomeScreen extends StatefulWidget {
  /// Inyección de [ApiService] para tests.
  final ApiService? apiOverride;

  /// Se invoca tras completar el onboarding (navega al Dashboard).
  final VoidCallback? onCompleted;

  const WelcomeScreen({
    super.key,
    this.apiOverride,
    this.onCompleted,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final ApiService _api;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
  }

  Future<void> _onStart() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    try {
      await _api.updateBusinessProfile({'onboarding_completed': true});
    } catch (_) {
      // Offline / error de red — igual marcamos el flag local para no
      // atrapar al dueño en la welcome. El backend reconcilia luego.
    }
    try {
      await AuthService().updateOnboardingCompleted(true);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sin AppBar — usamos un fondo gradient full-screen que envuelve
      // el contenido. Statusbar transparente para que el gradient suba
      // hasta el notch.
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Mismo azul brand del Dashboard (header) para coherencia
            // visual de toda la app.
            colors: [
              Color(0xFF1E3A8A),
              Color(0xFF3B82F6),
              Color(0xFF6366F1),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                // ── Hero — emoji grande dentro de un círculo con
                // gradient interno + sombra suave. Cumple el rol del
                // ícono 3D de los mockups sin agregar assets pesados.
                Center(
                  key: const Key('welcome_logo'),
                  child: _HeroIconBubble(),
                ),
                const SizedBox(height: 36),
                // ── Card glassmorphism — translúcida sobre el gradient,
                // con blur de fondo y borde claro. Misma idea que el
                // "Manage Project File Everywhere" de las capturas.
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding:
                          const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            '¡Bienvenido a VendIA!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Su negocio arranca con lo esencial: vender, '
                            'inventario y ganancias. Arriba en el panel '
                            'verá un carrusel con más opciones — '
                            'actívelas cuando las necesite.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              color:
                                  Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                // ── CTA pill grande — alto contraste sobre el
                // gradient, ≥56dp para Gerontodiseño.
                SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    key: const Key('welcome_start_button'),
                    onPressed: _submitting ? null : _onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E3A8A),
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: const StadiumBorder(),
                      shadowColor: Colors.transparent,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: Color(0xFF1E3A8A),
                            ),
                          )
                        : const Text(
                            'Empezar',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
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
}

/// Burbuja con gradient + emoji grande — placeholder de ilustración
/// 3D para el MVP. El emoji nativo se renderea con la fuente del
/// sistema, sin peso adicional en el bundle.
class _HeroIconBubble extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 1.0,
          colors: [
            Color(0xFFE0E7FF),
            Color(0xFFA5B4FC),
            Color(0xFF6366F1),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          // Doble sombra: una difusa que da el "flotando" y otra más
          // marcada cerca del borde para profundidad sin saturar.
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(-2, -4),
          ),
        ],
      ),
      child: const Center(
        // Emoji "tienda" — universal, no requiere asset bundled.
        child: Text(
          '🏪',
          style: TextStyle(fontSize: 96, height: 1.0),
        ),
      ),
    );
  }
}

