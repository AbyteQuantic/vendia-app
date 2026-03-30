import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../onboarding/onboarding_stepper.dart';

/// Modelo de sucursal para la pantalla de selección.
class BranchInfo {
  final int id;
  final String name;
  final String address;
  final bool onboardingComplete;
  final int? onboardingStep; // paso donde quedó, null si completo

  const BranchInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.onboardingComplete,
    this.onboardingStep,
  });

  factory BranchInfo.fromJson(Map<String, dynamic> json) {
    return BranchInfo(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Sin nombre',
      address: json['address'] as String? ?? '',
      onboardingComplete: json['onboarding_complete'] as bool? ?? false,
      onboardingStep: json['onboarding_step'] as int?,
    );
  }
}

/// Pantalla post-login: selección de sucursal.
/// Si el usuario tiene más de 1 sede, debe elegir antes de entrar al Dashboard.
class BranchSelectorScreen extends StatelessWidget {
  final List<BranchInfo> branches;
  final String ownerName;

  const BranchSelectorScreen({
    super.key,
    required this.branches,
    required this.ownerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'VendIA',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              Text(
                'Hola, $ownerName',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seleccione la sucursal donde va a trabajar hoy.',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Lista de sucursales
              Expanded(
                child: ListView.separated(
                  itemCount: branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final branch = branches[index];
                    return _BranchCard(
                      branch: branch,
                      onTap: () => _onBranchTap(context, branch),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBranchTap(BuildContext context, BranchInfo branch) {
    HapticFeedback.lightImpact();

    if (!branch.onboardingComplete) {
      // Ir al onboarding de esa sucursal
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const OnboardingStepperScreen(),
        ),
      );
      return;
    }

    // Ir al dashboard de esa sucursal
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => DashboardScreen(
          ownerName: ownerName,
          businessName: branch.name,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final BranchInfo branch;
  final VoidCallback onTap;

  const _BranchCard({
    required this.branch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = branch.onboardingComplete;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isReady ? AppTheme.surfaceGrey : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isReady
                ? AppTheme.borderColor
                : AppTheme.warning.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícono de la sucursal
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isReady
                    ? AppTheme.primary.withValues(alpha: 0.1)
                    : AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isReady
                    ? Icons.storefront_rounded
                    : Icons.warning_amber_rounded,
                size: 32,
                color: isReady ? AppTheme.primary : AppTheme.warning,
              ),
            ),
            const SizedBox(width: 16),

            // Info de la sucursal
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (branch.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      branch.address,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (!isReady) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '\u26A0\uFE0F Configuraci\u00F3n pendiente',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Flecha
            Icon(
              Icons.chevron_right_rounded,
              size: 32,
              color: isReady ? AppTheme.primary : AppTheme.warning,
            ),
          ],
        ),
      ),
    );
  }
}
