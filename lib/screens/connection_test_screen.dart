import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../core/network/api_client.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'onboarding/onboarding_stepper.dart';

/// Pantalla de prueba de conexión al backend local.
/// Gerontodiseño: botones grandes (min 60px), texto legible.
class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  bool _loading = false;
  bool _checkingSession = false;
  String? _message;
  bool? _success;

  Future<void> _testConnection() async {
    setState(() {
      _loading = true;
      _message = null;
      _success = null;
    });

    try {
      final result = await ApiClient().healthCheck();
      setState(() {
        _success = true;
        _message = '¡Conectado exitosamente!\nRespuesta: $result';
      });
    } on DioException catch (e) {
      setState(() {
        _success = false;
        _message = 'Error de conexión:\n${e.message ?? e.type.name}';
      });
    } catch (e) {
      setState(() {
        _success = false;
        _message = 'Error inesperado:\n$e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Verifica si hay sesión guardada y navega al flujo correcto.
  Future<void> _continueToApp() async {
    HapticFeedback.mediumImpact();
    setState(() => _checkingSession = true);

    try {
      final auth = AuthService();
      final hasSession = await auth.hasSession();

      if (!mounted) return;

      if (hasSession) {
        // Tiene token → directo al Dashboard
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen(ownerName: '', businessName: '')),
        );
      } else {
        // Sin sesión → Login
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (_) {
      // En caso de error, ir al Login
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  /// Ir directecto al Onboarding (registro nuevo)
  void _goToOnboarding() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingStepper()),
    );
  }

  /// Ir directo al Dashboard (modo demo sin backend)
  void _goToDashboardDemo() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DashboardScreen(ownerName: '', businessName: '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.point_of_sale_rounded,
                    color: Colors.white, size: 44),
              ),
              const SizedBox(height: 12),
              const Text(
                'VendIA',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const Text(
                'Su tienda, inteligente',
                style: TextStyle(fontSize: 18, color: Color(0xFF6B7280)),
              ),

              const SizedBox(height: 32),

              // URL del backend
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _success == true
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_outlined,
                      color: _success == true
                          ? const Color(0xFF10B981)
                          : const Color(0xFF6B7280),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ApiConfig.baseUrl,
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'monospace',
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Botón probar conexión
              SizedBox(
                height: 64,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _testConnection,
                  icon: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.wifi_find_rounded, size: 24),
                  label: Text(_loading
                      ? 'Conectando...'
                      : '🔌 Probar Conexión'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Resultado de conexión
              if (_message != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        _success! ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _success!
                          ? const Color(0xFF10B981)
                          : const Color(0xFFFF6B6B),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _success!
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        color: _success!
                            ? const Color(0xFF10B981)
                            : const Color(0xFFFF6B6B),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _success!
                                ? const Color(0xFF065F46)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // ── Botones de navegación ─────────────────────────────────

              // Botón principal: Continuar a la app
              SizedBox(
                height: 64,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checkingSession ? null : _continueToApp,
                  icon: _checkingSession
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.arrow_forward_rounded, size: 28),
                  label: const Text('Continuar a la App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Fila con 2 botones: Registrarse + Demo
              Row(
                children: [
                  // Ir al Onboarding (registro)
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _goToOnboarding,
                        icon: const Icon(Icons.person_add_rounded, size: 22),
                        label: const Text('Registrarse'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF764BA2),
                          side: const BorderSide(
                              color: Color(0xFF764BA2), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Ir al Dashboard (demo sin login)
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _goToDashboardDemo,
                        icon: const Icon(Icons.play_circle_outline_rounded,
                            size: 22),
                        label: const Text('Ver Demo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(
                              color: Color(0xFFF59E0B), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
