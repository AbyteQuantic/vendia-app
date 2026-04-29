import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../dashboard/dashboard_screen.dart';
import 'onboarding_stepper_controller.dart';
import 'steps/step_owner.dart';
import 'steps/step_business.dart';
import 'steps/step_branches.dart';
import 'steps/step_config.dart';
import 'steps/step_employees.dart';
import 'steps/step_logo.dart';

/// Punto de entrada público del Stepper de onboarding.
/// Crea el [OnboardingStepperController] con las dependencias reales
/// y lo inyecta via [ChangeNotifierProvider].
class OnboardingStepperScreen extends StatelessWidget {
  const OnboardingStepperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final api = ApiService(auth);

    return ChangeNotifierProvider(
      create: (_) => OnboardingStepperController(
        apiCall: (payload) => api.registerTenantFull(payload),
        saveSession: (data) async {
          // Wipe local Isar data so the new tenant starts clean.
          await DatabaseService.instance.clearAllData();

          // Backend returns feature_flags + business_types at the root
          // of the register/login response (migration 021). Fold them
          // into both the tenant map and the legacy path so the
          // dashboard can read them on first launch.
          final featureFlags =
              (data['feature_flags'] as Map<String, dynamic>?);
          final businessTypes = (data['business_types'] as List?)
              ?.whereType<String>()
              .toList();

          if (data.containsKey('access_token')) {
            final tenant = Map<String, dynamic>.from(
                (data['tenant'] as Map<String, dynamic>?) ?? {});
            if (featureFlags != null) tenant['feature_flags'] = featureFlags;
            if (businessTypes != null) tenant['business_types'] = businessTypes;
            await auth.saveSession(
              accessToken: data['access_token'] as String,
              refreshToken: data['refresh_token'] as String? ?? '',
              tenant: tenant,
            );
          } else {
            await auth.saveLegacySession(
              token: data['token'] as String,
              tenantId: data['tenant_id'].toString(),
              ownerName: data['owner_name'] as String,
              businessName: data['business_name'] as String,
              featureFlags: featureFlags,
              businessTypes: businessTypes,
            );
          }
        },
      ),
      child: const OnboardingStepper(),
    );
  }
}

/// Widget del stepper (testeable por separado via ChangeNotifierProvider.value).
class OnboardingStepper extends StatefulWidget {
  const OnboardingStepper({super.key});

  @override
  State<OnboardingStepper> createState() => _OnboardingStepperState();
}

class _OnboardingStepperState extends State<OnboardingStepper> {
  final _pageCtrl = PageController();
  late final OnboardingStepperController _ctrl;

  // Un FormKey por paso con campos de formulario
  final _formKeys = [
    GlobalKey<FormState>(), // Paso 1 — Propietario
    GlobalKey<FormState>(), // Paso 2 — Negocio
  ];

  // Títulos y subtítulos. Logo en step 5 (intent capture, sin API
  // calls), Empleados en step 6 — el botón "Crear cuenta" del paso 6
  // dispara registerTenantFull() y a continuación replays la
  // intención de logo capturada en el paso 5. Así, desde la
  // perspectiva del comerciante, "no se crea la cuenta sin la imagen
  // del negocio".
  static const _stepTitles = [
    ('Paso 1 de 6', 'Sus datos personales'),
    ('Paso 2 de 6', 'Datos del negocio'),
    ('Paso 3 de 6', '¿Tiene más de un local?'),
    ('Paso 4 de 6', '¿Qué vende en su negocio?'),
    ('Paso 5 de 6', 'La imagen de su negocio'),
    ('Paso 6 de 6', 'Sus empleados'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = context.read<OnboardingStepperController>();
    _ctrl.addListener(_onControllerChange);
  }

  void _onControllerChange() {
    if (!mounted) return;
    // submit() runs on step 6 (the new last step) and applies the
    // captured logo intent inline. On success we go straight to the
    // dashboard — no intermediate logo screen anymore because that
    // step now lives BEFORE registration.
    if (_ctrl.status == StepperStatus.success) {
      _finishOnboarding();
    }
  }

  void _finishOnboarding() {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => DashboardScreen(
          ownerName: '${_ctrl.ownerName} ${_ctrl.ownerLastName}'.trim(),
          businessName: _ctrl.businessName,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChange);
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Navegación ────────────────────────────────────────────────────────────

  void _onNext() {
    final step = _ctrl.currentStep;

    // Pasos con formulario: validar antes de avanzar
    if (step < 2) {
      if (!_formKeys[step].currentState!.validate()) return;
      _formKeys[step].currentState!.save();
    }

    // Paso 4 (config/portafolios): verificar que se seleccionó al menos un tipo
    if (step == 3) {
      if (_ctrl.businessTypes.isEmpty) {
        return;
      }
    }

    // Paso 5 (logo): obligatorio tener logo antes de avanzar
    if (step == 4) {
      if (_ctrl.logoUrl.isEmpty) {
        return;
      }
    }

    _ctrl.nextStep();
    _pageCtrl.animateToPage(
      _ctrl.currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onBack() {
    _ctrl.previousStep();
    _pageCtrl.animateToPage(
      _ctrl.currentStep,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<OnboardingStepperController>(
          builder: (ctx, ctrl, _) {
            final step = ctrl.currentStep;
            final (stepLabel, stepTitle) = _stepTitles[step];
            // Last step (índice 5 = "Sus empleados") dispara el
            // registro y, en éxito, replays el logo capturado en el
            // paso 5. Logo step (índice 4) es solo "Siguiente".
            final isRegisterStep =
                step == OnboardingStepperController.totalSteps - 1;
            final isLoading = ctrl.status == StepperStatus.loading;

            return Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo + cerrar
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.point_of_sale_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'VendIA',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(MaterialPageRoute(
                                    builder: (_) => const LoginScreen())),
                            child: const Text('Ya tengo cuenta',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 18)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Barra de progreso (5 segmentos)
                      Row(
                        children: List.generate(OnboardingStepperController.totalSteps, (i) {
                          final active = i <= step;
                          return Expanded(
                            child: Container(
                              height: 6,
                              margin: EdgeInsets.only(right: i < OnboardingStepperController.totalSteps - 1 ? 6 : 0),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppTheme.primary
                                    : AppTheme.borderColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Etiqueta de paso + título
                      Text(stepLabel,
                          style: const TextStyle(
                              fontSize: 18,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(stepTitle,
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary)),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Páginas ────────────────────────────────────────────────
                Expanded(
                  child: PageView(
                    controller: _pageCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      StepOwner(controller: ctrl, formKey: _formKeys[0]),
                      StepBusiness(controller: ctrl, formKey: _formKeys[1]),
                      const StepBranches(),
                      const StepConfig(),
                      const StepLogo(),
                      const StepEmployees(),
                    ],
                  ),
                ),

                // ── Error de API ───────────────────────────────────────────
                if (ctrl.status == StepperStatus.error)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppTheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppTheme.error, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(ctrl.errorMessage,
                                style: const TextStyle(
                                    color: AppTheme.error, fontSize: 18)),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Botones de navegación ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  child: Row(
                    children: [
                      // Botón Atrás (oculto en el paso 1)
                      if (step > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: OutlinedButton(
                            key: const Key('btn_back'),
                            onPressed: isLoading ? null : _onBack,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(64, 60),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              side: const BorderSide(
                                  color: AppTheme.primary, width: 1.5),
                            ),
                            child: const Icon(Icons.arrow_back_rounded,
                                color: AppTheme.primary, size: 26),
                          ),
                        ),

                      // Botón Siguiente / Crear cuenta. Dos modos
                      // tras mover el logo a step 5:
                      //   - pasos 1-5: "Siguiente" (avanza local)
                      //   - paso 6 (empleados, último): "Crear cuenta"
                      //     → submit() registra + replays la
                      //     intención de logo capturada en step 5;
                      //     _onControllerChange navega al dashboard
                      //     en éxito.
                      Expanded(
                        child: ElevatedButton(
                          key: isRegisterStep
                              ? const Key('btn_submit')
                              : const Key('btn_next'),
                          onPressed: isLoading
                              ? null
                              : isRegisterStep
                                  ? ctrl.submit
                                  : _onNext,
                          child: isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : Text(isRegisterStep
                                  ? 'Crear cuenta'
                                  : 'Siguiente'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
