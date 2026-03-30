import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 4 — Portafolios: selección MÚLTIPLE de tipos de negocio.
/// Chips gigantes con ícono + etiqueta (Gerontodiseño).
class StepConfig extends StatelessWidget {
  const StepConfig({super.key});

  static const _types = [
    _BusinessTypeOption(
      key: Key('btype_tienda'),
      value: 'tienda_barrio',
      label: 'Tienda /\nMinimercado',
      icon: Icons.store_rounded,
      description: 'Víveres, abarrotes\ny productos del día',
    ),
    _BusinessTypeOption(
      key: Key('btype_bar'),
      value: 'bar',
      label: 'Bar /\nLicorera',
      icon: Icons.local_bar_rounded,
      description: 'Bebidas, licores\ny entretenimiento',
    ),
    _BusinessTypeOption(
      key: Key('btype_comidas'),
      value: 'comidas_rapidas',
      label: 'Restaurante /\nComidas',
      icon: Icons.restaurant_rounded,
      description: 'Cocina, recetas\ny despacho de pedidos',
    ),
    _BusinessTypeOption(
      key: Key('btype_miscelanea'),
      value: 'miscelanea',
      label: 'Miscelánea /\nPapelería',
      icon: Icons.edit_note_rounded,
      description: 'Papelería, recargas\ny servicios varios',
    ),
    _BusinessTypeOption(
      key: Key('btype_muebles'),
      value: 'muebles',
      label: 'Mueblería /\nDecoración',
      icon: Icons.chair_rounded,
      description: 'Muebles, colchones\ny artículos del hogar',
    ),
    _BusinessTypeOption(
      key: Key('btype_manufactura'),
      value: 'manufactura',
      label: 'Fábrica /\nManufactura',
      icon: Icons.precision_manufacturing_rounded,
      description: 'Producción, insumos\ny control de costos',
    ),
    _BusinessTypeOption(
      key: Key('btype_reparacion'),
      value: 'reparacion',
      label: 'Reparación /\nRemodelación',
      icon: Icons.build_rounded,
      description: 'Servicios técnicos,\nrepuestos y presupuestos',
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
                  '¿Qué vende en su negocio?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Puede elegir varios si su negocio es mixto.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Grid 2x2 de tarjetas multi-selección
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _types.map((opt) {
                    final selected = ctrl.businessTypes.contains(opt.value);
                    return _TypeCard(
                      option: opt,
                      selected: selected,
                      onTap: () => ctrl.toggleBusinessType(opt.value),
                    );
                  }).toList(),
                ),

                // Resumen de selección
                if (ctrl.businessTypes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppTheme.success,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ctrl.businessTypes.length == 1
                                ? '1 portafolio seleccionado'
                                : '${ctrl.businessTypes.length} portafolios seleccionados',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Error inline si intenta avanzar sin seleccionar
                if (ctrl.businessTypes.isEmpty && ctrl.currentStep == 3)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Seleccione al menos un tipo de negocio',
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
        child: Stack(
          children: [
            // Checkbox indicator
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? Colors.white
                        : AppTheme.borderColor,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: AppTheme.primary,
                      )
                    : null,
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    option.icon,
                    size: 44,
                    color: selected ? Colors.white : AppTheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    option.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      color: selected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
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
  final String description;
  final IconData icon;

  const _BusinessTypeOption({
    required this.key,
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
  });
}
