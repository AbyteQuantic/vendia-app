// Catálogo canónico de tipos de negocio: valor backend → ícono + label
// legible. Fuente única para la barra de tipos del Dashboard
// (BusinessTypesBar). El grid de selección en
// `screens/dashboard/business_profile_screen.dart` mantiene su propia
// copia de la tupla (value, icon, label) — si agregas o renombras un
// tipo, sincroniza ambos.
//
// Los `value` deben coincidir EXACTO con los que emite el backend
// (migración de tenant). Hay alias legacy mapeados al ícono/label
// vigente para datos viejos.

import 'package:flutter/material.dart';

/// Metadatos de presentación de un tipo de negocio.
class BusinessTypeMeta {
  final String value;
  final IconData icon;
  final String label;

  const BusinessTypeMeta(this.value, this.icon, this.label);
}

/// Tipos de negocio seleccionables, en el mismo orden que el grid del
/// perfil de negocio.
const List<BusinessTypeMeta> kBusinessTypes = [
  BusinessTypeMeta('tienda_barrio', Icons.store_rounded, 'Tienda de Barrio'),
  BusinessTypeMeta(
      'minimercado', Icons.local_grocery_store_rounded, 'Minimercado'),
  BusinessTypeMeta('deposito_construccion', Icons.inventory_2_rounded,
      'Depósito / Ferretería'),
  BusinessTypeMeta('restaurante', Icons.restaurant_rounded, 'Restaurante'),
  BusinessTypeMeta('comidas_rapidas', Icons.fastfood_rounded, 'Comidas Rápidas'),
  BusinessTypeMeta('bar', Icons.local_bar_rounded, 'Bar / Discoteca'),
  BusinessTypeMeta(
      'manufactura', Icons.precision_manufacturing_rounded, 'Manufactura'),
  BusinessTypeMeta(
      'reparacion_muebles', Icons.build_rounded, 'Reparación / Servicios'),
  BusinessTypeMeta('emprendimiento_general', Icons.rocket_launch_rounded,
      'Emprendimiento'),
  // F042 — academias/institutos: su tipo activa el módulo de Eventos.
  BusinessTypeMeta('academias_instituciones', Icons.school_rounded,
      'Academias e Instituciones'),
  // Spec 075 — proveedores B2B: derivan EnableSupplierMode y los descubren las
  // tiendas cercanas en "Proveedores en VendIA".
  BusinessTypeMeta(
      'proveedor_mayorista', Icons.warehouse_rounded, 'Proveedor Mayorista'),
  BusinessTypeMeta('proveedor_agricola', Icons.grass_rounded, 'Proveedor Agrícola'),
  // Spec 084 — peluquerías, barberías y salones: servicios con profesionales,
  // turnos/citas y liquidación. Su tipo implica la capacidad de Servicios.
  BusinessTypeMeta(
      'peluqueria_barberia', Icons.content_cut_rounded, 'Peluquería / Barbería'),
];

/// Alias legacy → value vigente (mismo mapeo que el header del Dashboard).
const Map<String, String> _legacyAliases = {
  'muebles': 'reparacion_muebles',
  'reparacion': 'reparacion_muebles',
  'miscelanea': 'emprendimiento_general',
};

/// Resuelve los metadatos de un value (incluye alias legacy). Si el value
/// es desconocido, devuelve un meta genérico con el propio value como
/// label — nunca null, para que la UI no se rompa con datos inesperados.
BusinessTypeMeta businessTypeMeta(String value) {
  final canonical = _legacyAliases[value] ?? value;
  for (final m in kBusinessTypes) {
    if (m.value == canonical) return m;
  }
  return BusinessTypeMeta(value, Icons.storefront_rounded, value);
}
