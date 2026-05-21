// Spec: specs/023-capacidades-opcionales-negocio/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
//
// Mapa tipo-de-negocio → capacidades implícitas.
//
// FUENTE DE VERDAD: backend/internal/models/tenant.go → DefaultFeatureFlags
// Mantenlo en sincronía con esa función; si cambias la lógica allá,
// cámbiala aquí también.
//
// La regla es: una capacidad "implícita" para un tipo de negocio
// significa que el toggle correspondiente NO se muestra en la UI,
// porque el tipo ya la concede y no puede desactivarse.
//
// Backend (tenant.go):
//   food    := has(restaurante, comidas_rapidas, bar)
//   services := has(reparacion_muebles, manufactura, emprendimiento_general)
//
//   EnableTables          = food || hasTables (toggle)
//   EnableKDS             = food              (no toggle)
//   EnableTips            = food              (no toggle)
//   EnableServices        = services || offersServices (toggle)
//   EnableCustomBilling   = services || offersServices (toggle)
//   EnableFractionalUnits = deposito_construccion || sellsByWeight (toggle)

/// Capacidades opcionales que el tendero puede activar con un toggle.
enum OptionalCapability {
  /// "cobra servicios o trabajos por encargo"
  /// → enable_services + enable_custom_billing
  services,

  /// "vende productos a granel / fraccionados"
  /// → enable_fractional_units
  fractionalUnits,

  /// "atiende clientes en mesas"
  /// → enable_tables (sin KDS ni tips)
  tables,

  /// "maneja precios diferentes para mayorista y minorista" (F029)
  /// → enable_price_tiers
  ///
  /// Default OFF; no implícita en ningún tipo de negocio (incluso un
  /// depósito puede no necesitarla). El toggle siempre aparece como
  /// opción manual cuando la pantalla muestra capacidades opcionales.
  priceTiers,
}

/// Retorna las [OptionalCapability] que el [businessType] YA concede
/// de forma implícita. Un toggle para esa capacidad NO debe mostrarse.
///
/// Espejo de DefaultFeatureFlags en tenant.go — ver comentario de cabecera.
Set<OptionalCapability> impliedCapabilities(String? businessType) {
  if (businessType == null) return const {};

  final result = <OptionalCapability>{};

  // food → mesas implícitas
  const foodTypes = {
    'restaurante',
    'comidas_rapidas',
    'bar',
  };

  // services → servicios implícitos
  const serviceTypes = {
    'reparacion_muebles',
    'manufactura',
    'emprendimiento_general',
  };

  if (foodTypes.contains(businessType)) {
    result.add(OptionalCapability.tables);
  }

  if (serviceTypes.contains(businessType)) {
    result.add(OptionalCapability.services);
  }

  // deposito_construccion → granel implícito
  if (businessType == 'deposito_construccion') {
    result.add(OptionalCapability.fractionalUnits);
  }

  return result;
}

/// Retorna las capacidades opcionales que el [businessType] NO implica,
/// es decir, las que deben mostrarse como toggles al usuario.
Set<OptionalCapability> toggleableCapabilities(String? businessType) {
  return OptionalCapability.values.toSet().difference(
        impliedCapabilities(businessType),
      );
}
