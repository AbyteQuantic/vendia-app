// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// Compuerta post-login: decide qué pantalla mostrar después de
// autenticarse.
//
//   onboarding_completed == false  → WelcomeScreen (1ª vez, F037)
//   onboarding_completed == true   → DashboardScreen
//
// Centraliza el check para que login / splash / branch-selector no
// tengan que duplicar la lógica. Lee el flag cacheado por AuthService
// (offline-safe) — default `true`, así un tenant existente nunca ve la
// welcome (AC-10).
//
// F037 reemplazó el wizard de 3 pasos (`OnboardingWizardScreen`) por
// una pantalla única de bienvenida (`WelcomeScreen`).

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';
import 'welcome_screen.dart';

class PostLoginGate extends StatefulWidget {
  final String ownerName;
  final String businessName;

  const PostLoginGate({
    super.key,
    required this.ownerName,
    required this.businessName,
  });

  @override
  State<PostLoginGate> createState() => _PostLoginGateState();
}

class _PostLoginGateState extends State<PostLoginGate> {
  /// null mientras se resuelve el flag; true/false una vez resuelto.
  bool? _onboardingCompleted;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final auth = AuthService();
    bool completed = true;
    try {
      completed = await auth.getOnboardingCompleted();
    } catch (_) {
      // Fail-open: ante cualquier error mostramos el Dashboard, nunca
      // atrapamos al dueño en la welcome por una lectura fallida.
      completed = true;
    }
    if (!mounted) return;
    setState(() {
      _onboardingCompleted = completed;
    });
  }

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          ownerName: widget.ownerName,
          businessName: widget.businessName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _onboardingCompleted;
    if (resolved == null) {
      // Carga breve mientras se lee el flag del secure storage.
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (!resolved) {
      // Primer ingreso — mostramos la welcome screen. Al terminarla
      // navegamos al Dashboard.
      return WelcomeScreen(onCompleted: _goToDashboard);
    }

    return DashboardScreen(
      ownerName: widget.ownerName,
      businessName: widget.businessName,
    );
  }
}
