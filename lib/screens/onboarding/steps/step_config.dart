import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 4 — Categoría principal del negocio: SELECCIÓN ÚNICA.
///
/// Multi-select caused ambiguous feature-flag combinations in the
/// wild (e.g. bar + manufactura → enable_tables and enable_services
/// both on, which renders conflicting CTAs on the POS). A radio-style
/// grid mapped 1:1 to the 9 backend enums removes the ambiguity at
/// the source.
class StepConfig extends StatelessWidget {
  const StepConfig({super.key});

  // Values are the EXACT strings the backend whitelists
  // (models.ValidBusinessTypes / migration 020 CHECK). Labels follow
  // the Phase-4 brief. Changing a value here without a migration
  // breaks /register with HTTP 400 via handlers.validateBusinessTypes.
  static const _types = [
    _BusinessTypeOption(
      key: Key('btype_tienda'),
      value: 'tienda_barrio',
      label: 'Tienda de\nBarrio',
      icon: Icons.store_rounded,
      description: 'Víveres, abarrotes\ny productos del día',
    ),
    _BusinessTypeOption(
      key: Key('btype_minimercado'),
      value: 'minimercado',
      label: 'Minimercado',
      icon: Icons.local_grocery_store_rounded,
      description: 'Mayor variedad\ny productos frescos',
    ),
    _BusinessTypeOption(
      key: Key('btype_deposito'),
      value: 'deposito_construccion',
      label: 'Depósito /\nFerretería',
      icon: Icons.inventory_2_rounded,
      description: 'Materiales y\nunidades fraccionadas',
    ),
    _BusinessTypeOption(
      key: Key('btype_restaurante'),
      value: 'restaurante',
      label: 'Restaurante',
      icon: Icons.restaurant_rounded,
      description: 'Cocina, mesas\ny recetas',
    ),
    _BusinessTypeOption(
      key: Key('btype_comidas'),
      value: 'comidas_rapidas',
      label: 'Comidas\nRápidas',
      icon: Icons.fastfood_rounded,
      description: 'Turnos, domicilios\ny despacho de pedidos',
    ),
    _BusinessTypeOption(
      key: Key('btype_bar'),
      value: 'bar',
      label: 'Bar /\nDiscoteca',
      icon: Icons.local_bar_rounded,
      description: 'Bebidas, licores\ny entretenimiento',
    ),
    _BusinessTypeOption(
      key: Key('btype_manufactura'),
      value: 'manufactura',
      label: 'Manufactura',
      icon: Icons.precision_manufacturing_rounded,
      description: 'Producción, insumos\ny control de costos',
    ),
    _BusinessTypeOption(
      key: Key('btype_reparacion_muebles'),
      value: 'reparacion_muebles',
      label: 'Reparación /\nServicios',
      icon: Icons.build_rounded,
      description: 'Servicios técnicos\ny facturación por ítem',
    ),
    _BusinessTypeOption(
      key: Key('btype_emprendimiento'),
      value: 'emprendimiento_general',
      label: 'Emprendimiento\nGeneral',
      icon: Icons.rocket_launch_rounded,
      description: 'Servicios varios,\npapelería y más',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingStepperController>(
      builder: (_, ctrl, __) {
        final selectedValue =
            ctrl.businessTypes.isEmpty ? null : ctrl.businessTypes.first;
        return SingleChildScrollView(
          child: Container(
            key: const Key('step_config'),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seleccione la categoría principal de su negocio',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Elija una sola — la que mejor describa lo que vende la mayor parte del tiempo.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Radio-style grid: tap replaces the previous selection.
                // childAspectRatio dropped from 0.85 → 0.78: at the
                // previous ratio each card was ~3-5px short of the
                // natural height of [icon + title(2 lines) +
                // description(2 lines)] on 360dp devices and Flutter
                // painted the BOTTOM-OVERFLOWED debug stripe across
                // all cards. UI_RULES.md #3 — must render clean on
                // 360dp.
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.78,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _types.map((opt) {
                    final selected = selectedValue == opt.value;
                    return _TypeCard(
                      option: opt,
                      selected: selected,
                      onTap: () => ctrl.setPrimaryBusinessType(opt.value),
                    );
                  }).toList(),
                ),

                if (selectedValue != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    key: const Key('step_config_summary'),
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
                            'Categoría: ${_labelFor(selectedValue)}',
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

                // Inline error when the user tries to advance without
                // picking a category.
                if (selectedValue == null && ctrl.currentStep == 3)
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

  static String _labelFor(String value) {
    return _types
        .firstWhere(
          (o) => o.value == value,
          orElse: () => _types.first,
        )
        .label
        .replaceAll('\n', ' ');
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
    return Semantics(
      button: true,
      selected: selected,
      label: option.label.replaceAll('\n', ' '),
      child: GestureDetector(
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
              // Radio indicator — a filled dot inside an outlined
              // circle when selected. Communicates "single choice"
              // without changing the card's footprint.
              Positioned(
                top: 12,
                right: 12,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : AppTheme.borderColor,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Center(
                          child: Icon(
                            Icons.circle,
                            size: 12,
                            color: AppTheme.primary,
                          ),
                        )
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                // Flexible-wrapped texts so a long label/description
                // shrinks (with ellipsis) rather than overflowing the
                // card — defensive even with the bumped aspect ratio
                // above. Icon size trimmed from 44 → 38 to free a
                // few px for the description line on narrow screens.
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option.icon,
                      size: 38,
                      color: selected ? Colors.white : AppTheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        option.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                          color:
                              selected ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        option.description,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.85)
                              : Colors.grey.shade500,
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
