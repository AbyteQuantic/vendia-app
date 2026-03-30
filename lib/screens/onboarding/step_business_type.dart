import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import 'onboarding_controller.dart';

class BusinessTypeOption {
  final String id;
  final String label;
  final IconData icon;
  final String description;

  const BusinessTypeOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
  });
}

const _options = [
  BusinessTypeOption(
    id: 'tienda_barrio',
    label: 'Tienda de\nBarrio',
    icon: Icons.storefront_rounded,
    description: 'Víveres, confites\ny productos del día',
  ),
  BusinessTypeOption(
    id: 'minimercado',
    label: 'Mini-\nmercado',
    icon: Icons.local_grocery_store_rounded,
    description: 'Mayor variedad,\nproductos frescos',
  ),
  BusinessTypeOption(
    id: 'bar',
    label: 'Bar /\nCantina',
    icon: Icons.sports_bar_rounded,
    description: 'Bebidas, licores\ny snacks',
  ),
  BusinessTypeOption(
    id: 'comidas_rapidas',
    label: 'Comidas\nRápidas',
    icon: Icons.fastfood_rounded,
    description: 'Turnos, recetas\ne insumos',
  ),
  BusinessTypeOption(
    id: 'miscelanea',
    label: 'Miscelánea\n/ Papelería',
    icon: Icons.edit_note_rounded,
    description: 'Papelería, internet\ny minutos',
  ),
];

class StepBusinessType extends StatelessWidget {
  final OnboardingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  const StepBusinessType({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<OnboardingController>(
        builder: (context, ctrl, _) {
          final isLoading = ctrl.status == OnboardingStatus.loading;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Qué tipo de\nnegocio tiene?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Toque la tarjeta que mejor lo describa.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),

              // Grid de tarjetas grandes
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.9,
                  children: _options.map((opt) {
                    final isSelected = ctrl.businessType == opt.id;
                    return _BusinessCard(
                      option: opt,
                      isSelected: isSelected,
                      onTap: () => ctrl.selectBusinessType(opt.id),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),

              if (ctrl.status == OnboardingStatus.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    ctrl.errorMessage,
                    style: const TextStyle(color: AppTheme.error, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),

              ElevatedButton(
                onPressed: ctrl.canSubmit && !isLoading ? onSubmit : null,
                child: isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('¡Empezar ahora! 🚀'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: isLoading ? null : onBack,
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                ),
                child: const Text(
                  '← Volver',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final BusinessTypeOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.borderColor,
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              option.icon,
              size: 52,
              color: isSelected ? Colors.white : AppTheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              option.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
