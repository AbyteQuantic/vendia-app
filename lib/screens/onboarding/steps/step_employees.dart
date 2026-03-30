import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 4 — Empleados: pregunta simple Sí/No con tarjetas grandes.
/// Si responde NO → mensaje claro de cajero por defecto.
class StepEmployees extends StatelessWidget {
  const StepEmployees({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingStepperController>(
      builder: (_, ctrl, __) {
        return SingleChildScrollView(
          child: Container(
            key: const Key('step_employees'),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Tienes empleados que\nusarán la caja?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Podrás agregar más empleados después.',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 32),

                // Tarjetas SÍ / NO
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceCard(
                        keyVal: const Key('emp_yes'),
                        label: 'SÍ, tengo\nempleados',
                        icon: Icons.group_rounded,
                        selected: ctrl.hasEmployees == true,
                        onTap: () => ctrl.setHasEmployees(true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ChoiceCard(
                        keyVal: const Key('emp_no'),
                        label: 'NO, solo\nyo vendo',
                        icon: Icons.person_rounded,
                        selected: ctrl.hasEmployees == false,
                        onTap: () => ctrl.setHasEmployees(false),
                      ),
                    ),
                  ],
                ),

                // Mensaje contextual cuando elige NO
                if (ctrl.hasEmployees == false) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: AppTheme.primary, size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Te asignaremos como el cajero principal por defecto',
                            style: TextStyle(
                              fontSize: 18,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Mensaje cuando elige SÍ
                if (ctrl.hasEmployees == true) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: AppTheme.success, size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Podrás registrar empleados desde el módulo Administrar una vez terminado el registro.',
                            style: TextStyle(
                              fontSize: 18,
                              color: AppTheme.success,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final Key keyVal;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.keyVal,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: keyVal,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 52,
              color: selected ? Colors.white : AppTheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.3,
                color: selected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
