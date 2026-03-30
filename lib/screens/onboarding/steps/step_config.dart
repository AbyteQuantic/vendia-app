import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 3 — Configuración: el usuario elige el tipo de negocio.
/// Cuatro tarjetas grandes con ícono + etiqueta (accesibilidad para adultos mayores).
class StepConfig extends StatelessWidget {
  const StepConfig({super.key});

  static const _types = [
    _BusinessTypeOption(
      key: Key('btype_tienda_barrio'),
      value: 'tienda_barrio',
      label: 'Tienda de\nBarrio',
      icon: Icons.store_rounded,
    ),
    _BusinessTypeOption(
      key: Key('btype_minimercado'),
      value: 'minimercado',
      label: 'Mini-\nmercado',
      icon: Icons.shopping_basket_rounded,
    ),
    _BusinessTypeOption(
      key: Key('btype_bar'),
      value: 'bar',
      label: 'Bar /\nCantina',
      icon: Icons.local_bar_rounded,
    ),
    _BusinessTypeOption(
      key: Key('btype_comidas_rapidas'),
      value: 'comidas_rapidas',
      label: 'Comidas\nRápidas',
      icon: Icons.fastfood_rounded,
    ),
    _BusinessTypeOption(
      key: Key('btype_miscelanea'),
      value: 'miscelanea',
      label: 'Miscelánea\n/ Papelería',
      icon: Icons.edit_note_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingStepperController>(
      builder: (_, ctrl, __) {
        return SingleChildScrollView(
          child: Container(
            key: const Key('step_config'),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Qué tipo de negocio tienes?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toca la tarjeta que mejor describa tu negocio.',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),

                // Grid 2×2 de tarjetas
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _types.map((opt) {
                    final selected = ctrl.businessType == opt.value;
                    return _TypeCard(
                      option: opt,
                      selected: selected,
                      onTap: () => ctrl.selectBusinessType(opt.value),
                    );
                  }).toList(),
                ),

                // Error inline si intenta avanzar sin seleccionar
                if (ctrl.businessType.isEmpty && ctrl.currentStep == 2)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Seleccione el tipo de negocio',
                      style: TextStyle(color: AppTheme.error, fontSize: 18),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TypeCard extends StatelessWidget {
  final _BusinessTypeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: option.key,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              option.icon,
              size: 48,
              color: selected ? Colors.white : AppTheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              option.label,
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

class _BusinessTypeOption {
  final Key key;
  final String value;
  final String label;
  final IconData icon;

  const _BusinessTypeOption({
    required this.key,
    required this.value,
    required this.label,
    required this.icon,
  });
}
