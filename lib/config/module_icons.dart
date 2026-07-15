// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Set fijo de íconos soportados (D5): clave estable → IconData compilado.
// Para módulos del catálogo que NO existen en el bundle compilado, el
// dashboard usa este mapa para pintar su ícono. Mantener en sync con el
// IconPicker del admin-web.

import 'package:flutter/material.dart';

const Map<String, IconData> _icons = {
  'point_of_sale_rounded': Icons.point_of_sale_rounded,
  'receipt_long_rounded': Icons.receipt_long_rounded,
  'bar_chart_rounded': Icons.bar_chart_rounded,
  'description_outlined': Icons.description_outlined,
  'inventory_2_rounded': Icons.inventory_2_rounded,
  'assessment_rounded': Icons.assessment_rounded,
  'local_shipping_rounded': Icons.local_shipping_rounded,
  'kitchen_rounded': Icons.kitchen_rounded,
  'restaurant_menu_rounded': Icons.restaurant_menu_rounded,
  'soup_kitchen_rounded': Icons.soup_kitchen_rounded,
  'shopping_cart_rounded': Icons.shopping_cart_rounded,
  'handyman_rounded': Icons.handyman_rounded,
  'people_outline': Icons.people_outline,
  'campaign_rounded': Icons.campaign_rounded,
  'auto_awesome_rounded': Icons.auto_awesome_rounded,
  'settings_rounded': Icons.settings_rounded,
  'storefront_rounded': Icons.storefront_rounded,
  // F042 — módulo de Eventos.
  'event_rounded': Icons.event_rounded,
};

/// Ícono para una clave del catálogo; fallback genérico si es desconocida.
IconData iconForKey(String key) => _icons[key] ?? Icons.widgets_rounded;
