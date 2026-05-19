// Spec: specs/023-capacidades-opcionales-negocio/spec.md
//
// Widget reutilizable: sección "¿Su negocio también…?" con hasta 3
// SwitchListTile para las capacidades opcionales del tenant.
//
// Usado en:
//   - onboarding/steps/step_config.dart  (onboarding)
//   - dashboard/business_profile_screen.dart (editar negocio)
//
// El mapa tipo→capacidades implícitas está en
//   lib/utils/business_capability_map.dart
// que espeja DefaultFeatureFlags en backend/internal/models/tenant.go.

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/business_capability_map.dart';

/// Sección de capacidades opcionales.
///
/// [selectedType]   → tipo principal elegido; si es null, el widget
///                    no se muestra.
/// [flags]          → feature_flags actuales del tenant (para derivar
///                    el estado inicial en la pantalla de perfil).
///                    En onboarding se puede pasar FeatureFlags() vacío.
/// [offersServices] → ValueNotifier del toggle "cobra servicios".
/// [sellsByWeight]  → ValueNotifier del toggle "vende a granel".
/// [hasTables]      → ValueNotifier del toggle "atiende en mesas".
class OptionalCapabilitiesSection extends StatelessWidget {
  final String? selectedType;
  final FeatureFlags flags;
  final ValueNotifier<bool> offersServices;
  final ValueNotifier<bool> sellsByWeight;
  final ValueNotifier<bool> hasTables;

  const OptionalCapabilitiesSection({
    super.key,
    required this.selectedType,
    required this.flags,
    required this.offersServices,
    required this.sellsByWeight,
    required this.hasTables,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedType == null) return const SizedBox.shrink();

    final toggleable = toggleableCapabilities(selectedType);
    if (toggleable.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('optional_caps_section'),
      margin: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Su negocio también…?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Active lo que aplique — puede cambiarlo después.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Column(
              children: _buildTiles(toggleable),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTiles(Set<OptionalCapability> toggleable) {
    final tiles = <Widget>[];
    final ordered = [
      OptionalCapability.services,
      OptionalCapability.fractionalUnits,
      OptionalCapability.tables,
    ].where(toggleable.contains).toList();

    for (var i = 0; i < ordered.length; i++) {
      final cap = ordered[i];
      final showDivider = i < ordered.length - 1;

      switch (cap) {
        case OptionalCapability.services:
          tiles.add(_CapabilityTile(
            tileKey: const Key('toggle_services'),
            title: 'Cobra servicios o trabajos por encargo',
            subtitle: 'Ej: arreglos, instalaciones, cortes a domicilio',
            notifier: offersServices,
            showDivider: showDivider,
          ));
        case OptionalCapability.fractionalUnits:
          tiles.add(_CapabilityTile(
            tileKey: const Key('toggle_fractional'),
            title: 'Vende productos a granel o fraccionados',
            subtitle: 'Ej: arroz por libra, aceite por litro, granos',
            notifier: sellsByWeight,
            showDivider: showDivider,
          ));
        case OptionalCapability.tables:
          tiles.add(_CapabilityTile(
            tileKey: const Key('toggle_tables'),
            title: 'Atiende clientes en mesas',
            subtitle: 'Ej: sala de espera, mesas de juego, comedor',
            notifier: hasTables,
            showDivider: showDivider,
          ));
      }
    }

    return tiles;
  }
}

class _CapabilityTile extends StatelessWidget {
  final Key tileKey;
  final String title;
  final String subtitle;
  final ValueNotifier<bool> notifier;
  final bool showDivider;

  const _CapabilityTile({
    required this.tileKey,
    required this.title,
    required this.subtitle,
    required this.notifier,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: notifier,
          builder: (_, value, __) => SwitchListTile(
            key: tileKey,
            value: value,
            onChanged: (v) => notifier.value = v,
            activeThumbColor: AppTheme.primary,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}
