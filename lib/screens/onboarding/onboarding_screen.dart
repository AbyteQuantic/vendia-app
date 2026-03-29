import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';
import 'onboarding_controller.dart';
import 'step_identity.dart';
import 'step_phone.dart';
import 'step_business_type.dart';

// Total de pasos en el stepper (incluyendo la contraseña integrada en paso 2)
const _totalSteps = 3;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final AuthService _authService;
  late final ApiService _apiService;
  late final OnboardingController _controller;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiService = ApiService(_authService);
    _controller = OnboardingController(_apiService, _authService);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handleSubmit() async {
    await _controller.submit();
    if (_controller.status == OnboardingStatus.success && mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => DashboardScreen(
            ownerName: _controller.ownerName,
            businessName: _controller.businessName,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity:
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                _StepperIndicator(controller: _controller),
                const SizedBox(height: 32),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // Paso 1: Nombre dueño + nombre tienda
                      StepIdentity(
                        controller: _controller,
                        onNext: () => _goToPage(1),
                      ),
                      // Paso 2: Teléfono (el campo PIN está integrado aquí)
                      StepPhone(
                        controller: _controller,
                        onNext: () => _goToPage(2),
                        onBack: () => _goToPage(0),
                      ),
                      // Paso 3: Tipo de negocio → submit
                      StepBusinessType(
                        controller: _controller,
                        onSubmit: _handleSubmit,
                        onBack: () => _goToPage(1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperIndicator extends StatelessWidget {
  final OnboardingController controller;
  const _StepperIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<OnboardingController>(
        builder: (_, ctrl, __) {
          return Row(
            children: List.generate(_totalSteps, (i) {
              final isDone = i < ctrl.currentStep;
              final isActive = i == ctrl.currentStep;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 6,
                        decoration: BoxDecoration(
                          color: isDone || isActive
                              ? AppTheme.primary
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    if (i < _totalSteps - 1) const SizedBox(width: 8),
                  ],
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
