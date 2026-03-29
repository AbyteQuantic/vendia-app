import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../onboarding/onboarding_stepper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  late final AuthService _auth;
  late final ApiService _api;

  bool _isLoading = false;
  bool _pinVisible = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _auth = AuthService();
    _api = ApiService(_auth);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _api.login(
        phone: _phoneCtrl.text.trim(),
        password: _pinCtrl.text.trim(),
      );

      // Support both old and new API response formats
      if (data.containsKey('access_token')) {
        await _auth.saveSession(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String? ?? '',
          tenant: (data['tenant'] as Map<String, dynamic>?) ?? {},
        );
      } else {
        await _auth.saveLegacySession(
          token: data['token'] as String,
          tenantId: data['tenant_id'] as int,
          ownerName: data['owner_name'] as String,
          businessName: data['business_name'] as String,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => DashboardScreen(
            ownerName: data['owner_name'] as String,
            businessName: data['business_name'] as String,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity:
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } on AppError catch (e) {
      if (e.statusCode == 401) {
        HapticFeedback.heavyImpact();
        setState(() =>
            _errorMessage = 'Número o clave incorrectos. Intente de nuevo.');
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _errorMessage = e.message);
      }
    } on Exception catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMessage = AppError.fromException(e).message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Pantalla de inicio de sesión',
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 52),

                // ── Logo / Marca ─────────────────────────────────────────────
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.point_of_sale_rounded,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(height: 24),

                Text('Bienvenido\nde nuevo',
                    style: Theme.of(context).textTheme.displayLarge),
                const SizedBox(height: 8),
                const Text(
                  'Ingrese su número y clave para entrar.',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 48),

                // ── Formulario ───────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Teléfono
                      const Text('Número de celular',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        style:
                            const TextStyle(fontSize: 20, letterSpacing: 1.5),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: '310 000 0000',
                          prefixIcon: Icon(Icons.phone_outlined,
                              color: AppTheme.primary, size: 26),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Ingrese su número';
                          if (v.length < 7) return 'Número muy corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // PIN / Clave
                      const Text('Clave de acceso',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _pinCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: !_pinVisible,
                        style: const TextStyle(fontSize: 22, letterSpacing: 6),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          hintText: '• • • •',
                          prefixIcon: const Icon(Icons.lock_outline,
                              color: AppTheme.primary, size: 26),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _pinVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppTheme.textSecondary,
                            ),
                            tooltip:
                                _pinVisible ? 'Ocultar clave' : 'Mostrar clave',
                            onPressed: () =>
                                setState(() => _pinVisible = !_pinVisible),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Ingrese su clave';
                          if (v.length < 4) return 'Clave muy corta';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Error inline
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppTheme.error.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppTheme.error, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                      color: AppTheme.error, fontSize: 18),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 32),

                      // Botón de ingreso
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Entrar a mi tienda'),
                      ),

                      const SizedBox(height: 20),

                      // Link a registro
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const OnboardingStepperScreen(),
                              ),
                            );
                          },
                          child: const Text.rich(
                            TextSpan(
                              text: '¿Es su primera vez? ',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 18),
                              children: [
                                TextSpan(
                                  text: 'Registre su tienda',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
