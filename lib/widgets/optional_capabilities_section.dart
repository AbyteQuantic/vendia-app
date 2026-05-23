// Spec: specs/023-capacidades-opcionales-negocio/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
// Spec: specs/030-administracion-clientes-no-tienda/spec.md
// Spec: specs/031-cotizaciones/spec.md
// Spec: specs/033-difusion-promociones/spec.md
//
// Widget reutilizable: sección "¿Su negocio también…?" con
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
/// [enablePriceTiers] (F029) → ValueNotifier del toggle "Manejo precios
///                    diferentes para mayorista y minorista". Cuando es
///                    true, el widget expone tres TextField para los
///                    nombres de los tiers.
/// [priceTier1NameCtrl] (F029) → controller del nombre del tier 1.
/// [priceTier2NameCtrl] (F029) → controller del nombre del tier 2.
/// [priceTier3NameCtrl] (F029) → controller del nombre del tier 3.
/// [enableCustomerManagement] (F030) → ValueNotifier del toggle "Gestión
///                    de clientes". Cuando el padre no lo cablea (ej.
///                    onboarding), el toggle no se renderiza — misma
///                    invariante que priceTiers.
class OptionalCapabilitiesSection extends StatelessWidget {
  final String? selectedType;
  final FeatureFlags flags;
  final ValueNotifier<bool> offersServices;
  final ValueNotifier<bool> sellsByWeight;
  final ValueNotifier<bool> hasTables;

  // F029 — bound from the parent so business_profile_screen
  // gathers the values for the PATCH payload without piping
  // each TextField through Provider.
  final ValueNotifier<bool>? enablePriceTiers;
  final TextEditingController? priceTier1NameCtrl;
  final TextEditingController? priceTier2NameCtrl;
  final TextEditingController? priceTier3NameCtrl;

  // F030 — toggle "Gestión de clientes". Igual que priceTiers: el padre
  // (business_profile_screen) cablea el ValueNotifier; si es null el
  // toggle no se muestra.
  final ValueNotifier<bool>? enableCustomerManagement;

  // F031 — toggle "Cotizaciones". Misma invariante: el padre cablea el
  // ValueNotifier; si es null el toggle no se renderiza.
  final ValueNotifier<bool>? enableQuotes;

  // F033 — toggle "Promociones". Misma invariante: el padre cablea el
  // ValueNotifier; si es null el toggle no se renderiza.
  final ValueNotifier<bool>? enablePromotions;

  const OptionalCapabilitiesSection({
    super.key,
    required this.selectedType,
    required this.flags,
    required this.offersServices,
    required this.sellsByWeight,
    required this.hasTables,
    this.enablePriceTiers,
    this.priceTier1NameCtrl,
    this.priceTier2NameCtrl,
    this.priceTier3NameCtrl,
    this.enableCustomerManagement,
    this.enableQuotes,
    this.enablePromotions,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedType == null) return const SizedBox.shrink();

    final toggleable = toggleableCapabilities(selectedType);
    // F029: el toggle priceTiers solo se muestra cuando el parent
    // proporcionó los controllers. En onboarding aún no lo cableamos,
    // así que el set se queda como está. Cuando los controllers vienen,
    // forzamos su inclusión aunque toggleableCapabilities ya lo trae —
    // mantenemos la invariante "no se renderiza sin destino donde
    // guardar los nombres".
    final hasTierWiring = enablePriceTiers != null &&
        priceTier1NameCtrl != null &&
        priceTier2NameCtrl != null &&
        priceTier3NameCtrl != null;
    // F030: el toggle customerManagement solo se renderiza cuando el
    // padre cableó su ValueNotifier — misma invariante que priceTiers.
    final hasCustomerWiring = enableCustomerManagement != null;
    // F031: el toggle quotes solo se renderiza cuando el padre cableó
    // su ValueNotifier — misma invariante.
    final hasQuotesWiring = enableQuotes != null;
    // F033: el toggle promotions solo se renderiza cuando el padre
    // cableó su ValueNotifier — misma invariante.
    final hasPromotionsWiring = enablePromotions != null;
    final visible = toggleable.where((c) {
      if (c == OptionalCapability.priceTiers) return hasTierWiring;
      if (c == OptionalCapability.customerManagement) return hasCustomerWiring;
      if (c == OptionalCapability.quotes) return hasQuotesWiring;
      if (c == OptionalCapability.promotions) return hasPromotionsWiring;
      return true;
    }).toSet();
    if (visible.isEmpty) return const SizedBox.shrink();

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
              children: _buildTiles(visible),
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
      OptionalCapability.priceTiers,
      OptionalCapability.customerManagement,
      OptionalCapability.quotes,
      OptionalCapability.promotions,
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
        case OptionalCapability.priceTiers:
          tiles.add(_PriceTiersTile(
            notifier: enablePriceTiers!,
            tier1Ctrl: priceTier1NameCtrl!,
            tier2Ctrl: priceTier2NameCtrl!,
            tier3Ctrl: priceTier3NameCtrl!,
            showDivider: showDivider,
          ));
        case OptionalCapability.customerManagement:
          tiles.add(_CapabilityTile(
            tileKey: const Key('toggle_customer_management'),
            title: 'Gestión de clientes',
            subtitle: 'Sepa quién le compra: registre clientes y vea '
                'su historial de compras',
            notifier: enableCustomerManagement!,
            showDivider: showDivider,
          ));
        case OptionalCapability.quotes:
          tiles.add(_CapabilityTile(
            tileKey: const Key('toggle_quotes'),
            title: 'Cotizaciones',
            subtitle: 'Arme propuestas de precio para sus clientes '
                'antes de la venta',
            notifier: enableQuotes!,
            showDivider: showDivider,
          ));
        case OptionalCapability.promotions:
          tiles.add(_CapabilityTile(
            tileKey: const Key('toggle_promotions'),
            title: 'Promociones',
            subtitle: 'Avísele a sus clientes por WhatsApp cuando '
                'tenga ofertas o productos nuevos',
            notifier: enablePromotions!,
            showDivider: showDivider,
          ));
        case OptionalCapability.marketingHub:
          // F037: Marketing Hub se activa desde "Capacidades del
          // negocio" / reel del Dashboard, no desde esta sección de
          // negocio. No agregamos tile acá.
          break;
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

// F029 — tile especializado: SwitchListTile + sub-form con 3 inputs
// para renombrar los tiers. El sub-form vive bajo un AnimatedSize para
// que el alto del widget cambie sin saltos visuales bruscos en pantallas
// de 360dp.
class _PriceTiersTile extends StatelessWidget {
  final ValueNotifier<bool> notifier;
  final TextEditingController tier1Ctrl;
  final TextEditingController tier2Ctrl;
  final TextEditingController tier3Ctrl;
  final bool showDivider;

  const _PriceTiersTile({
    required this.notifier,
    required this.tier1Ctrl,
    required this.tier2Ctrl,
    required this.tier3Ctrl,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: notifier,
          builder: (_, value, __) => Column(
            children: [
              SwitchListTile(
                key: const Key('toggle_price_tiers'),
                value: value,
                onChanged: (v) => notifier.value = v,
                activeThumbColor: AppTheme.primary,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: const Text(
                  'Manejo precios diferentes para mayorista y minorista',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Ej: precio mayorista x12, mayorista x6 y detal',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: value
                    ? Padding(
                        key: const Key('price_tiers_subform'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Nombres de los tiers',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            _TierNameField(
                              fieldKey:
                                  const Key('price_tier_1_name'),
                              label: 'Tier 1',
                              hint: 'Ej: Depósito contado',
                              controller: tier1Ctrl,
                            ),
                            const SizedBox(height: 10),
                            _TierNameField(
                              fieldKey:
                                  const Key('price_tier_2_name'),
                              label: 'Tier 2',
                              hint: 'Ej: Depósito crédito',
                              controller: tier2Ctrl,
                            ),
                            const SizedBox(height: 10),
                            _TierNameField(
                              fieldKey:
                                  const Key('price_tier_3_name'),
                              label: 'Tier 3',
                              hint: 'Ej: Cliente final',
                              controller: tier3Ctrl,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _TierNameField extends StatelessWidget {
  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;

  const _TierNameField({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          maxLength: 50,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
