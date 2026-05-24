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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

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
      backgroundColor: const Color(0xFFFFFBF7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Logo / ícono de VendIA — usamos el ícono de tienda
              // tematizado mientras no hay un asset bundled. El
              // posicionamiento centrado + tamaño grande funciona como
              // anchor visual para el tendero 50+.
              Center(
                key: const Key('welcome_logo'),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E3A8A)
                            .withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '¡Bienvenido a VendIA!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Su negocio arranca con lo esencial: vender, '
                'inventario y ganancias.\n\n'
                'Arriba en el panel verá un carrusel con todas '
                'las opciones extra disponibles — actívelas '
                'cuando las necesite.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 60,
                child: ElevatedButton(
                  key: const Key('welcome_start_button'),
                  onPressed: _submitting ? null : _onStart,
                  child: _submitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Empezar',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
