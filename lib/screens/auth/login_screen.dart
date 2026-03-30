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
  final _phoneFocus = FocusNode();
  final _pinFocus = FocusNode();

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
    _phoneFocus.addListener(() => setState(() {}));
    _pinFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _phoneFocus.dispose();
    _pinFocus.dispose();
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
      HapticFeedback.heavyImpact();
      if (e.statusCode == 401) {
        setState(() =>
            _errorMessage = 'Número o clave incorrectos. Intente de nuevo.');
      } else {
        setState(() => _errorMessage = e.message);
      }
    } on Exception catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMessage = AppError.fromException(e).message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Estilo premium Gerontodesign v3.0 para campos ────────────────────────
  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    bool isPin = false,
    bool italic = true,
    Widget? suffixIcon,
    bool focused = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.grey.shade400,
        fontWeight: FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontSize: isPin ? 22 : 18,
      ),
      prefixIcon: Icon(
        icon,
        color: focused ? AppTheme.primary : const Color(0xFF9CA3AF),
        size: 26,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: focused ? Colors.white : const Color(0xFFF8F7F5),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFE8E4DF),
          width: 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.primary, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.error, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.error, width: 2.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 1. Fondo degradado cálido premium
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFBF7), // crema cálido arriba
              Color(0xFFF0F2F8), // azul-gris pálido abajo
            ],
          ),
        ),
        child: Semantics(
          label: 'Pantalla de inicio de sesión',
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),

                  // ── 2. Logo premium con doble sombra ──────────────────────
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF667EEA),
                          Color(0xFF1A2FA0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.point_of_sale_rounded,
                        color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 28),

                  // ── 3. Título con peso máximo ─────────────────────────────
                  const Text(
                    'Bienvenido\nde nuevo',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                      letterSpacing: -1.0,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── 4. Subtítulo ──────────────────────────────────────────
                  const Text(
                    'Ingrese su número y clave para entrar.',
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF666666),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 44),

                  // ── 5. Formulario con campos Gerontodesign ────────────────
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Label teléfono
                        const Text('Número de celular',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 10),

                        // Campo teléfono con sombra neutra
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha:
                                        _phoneFocus.hasFocus ? 0.08 : 0.05),
                                blurRadius:
                                    _phoneFocus.hasFocus ? 14 : 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _phoneCtrl,
                            focusNode: _phoneFocus,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(
                                fontSize: 20, letterSpacing: 1.5),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              hint: 'Ej: 310 000 0000',
                              icon: Icons.phone_rounded,
                              focused: _phoneFocus.hasFocus,
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Ingrese su número';
                              }
                              if (v.length < 7) return 'Número muy corto';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Label clave
                        const Text('Clave de acceso',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 10),

                        // Campo PIN con sombra neutra
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha:
                                        _pinFocus.hasFocus ? 0.08 : 0.05),
                                blurRadius:
                                    _pinFocus.hasFocus ? 14 : 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _pinCtrl,
                            focusNode: _pinFocus,
                            keyboardType: TextInputType.number,
                            obscureText: !_pinVisible,
                            style: const TextStyle(
                                fontSize: 22, letterSpacing: 6),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(8),
                            ],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleLogin(),
                            decoration: _inputDecoration(
                              hint: '• • • •',
                              icon: Icons.lock_rounded,
                              isPin: true,
                              italic: false,
                              focused: _pinFocus.hasFocus,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _pinVisible
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: AppTheme.textSecondary,
                                ),
                                tooltip: _pinVisible
                                    ? 'Ocultar clave'
                                    : 'Mostrar clave',
                                onPressed: () =>
                                    setState(() => _pinVisible = !_pinVisible),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Ingrese su clave';
                              }
                              if (v.length < 4) return 'Clave muy corta';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Error inline con estilo premium
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color:
                                      AppTheme.error.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
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

                        // ── 6. Botón premium con degradado y sombra neutra ──
                        Container(
                          width: double.infinity,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF1A2FA0),
                                Color(0xFF2541B2),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _isLoading ? null : _handleLogin,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5),
                                      )
                                    : const Text(
                                        'Entrar a mi negocio',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── 7. Link registro con underline dotted ───────────
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const OnboardingStepperScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(60, 60),
                            ),
                            child: const Text.rich(
                              TextSpan(
                                text: '¿Es su primera vez? ',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 18,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Registre su negocio',
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                      decorationColor: AppTheme.primary,
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
      ),
    );
  }
}
