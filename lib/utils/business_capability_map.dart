// Spec: specs/023-capacidades-opcionales-negocio/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
// Spec: specs/030-administracion-clientes-no-tienda/spec.md
// Spec: specs/031-cotizaciones/spec.md
// Spec: specs/033-difusion-promociones/spec.md
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

  /// "quiere saber quién le compra" (F030)
  /// → enable_customer_management
  ///
  /// Default OFF; no implícita en ningún tipo de negocio — la decide el
  /// dueño, no el tipo (decisión D4 del plan 030). El toggle siempre
  /// aparece como opción manual cuando la pantalla muestra capacidades
  /// opcionales. Cuando está ON: el checkout muestra un tile "Cliente",
  /// el menú principal muestra "Mis clientes" y toda venta puede
  /// asociarse a un cliente.
  customerManagement,

  /// "le piden cotizaciones antes de comprar" (F031)
  /// → enable_quotes
  ///
  /// Default OFF; no implícita en ningún tipo de negocio — la decide el
  /// dueño (ferretería, taller, repostería por encargo la usan; tiendas
  /// de contado no). El toggle siempre aparece como opción manual.
  /// Cuando está ON: el menú principal muestra "Cotizaciones".
  quotes,

  /// "quiere avisarle promociones a sus clientes" (F033)
  /// → enable_promotions
  ///
  /// Default OFF; no implícita en ningún tipo de negocio — la decide el
  /// dueño. El toggle siempre aparece como opción manual. Cuando está
  /// ON: el menú principal muestra "Promociones" y el dueño puede armar
  /// campañas de difusión y enviarlas por WhatsApp / link público.
  promotions,
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

/// F036 — capacidades que se pre-activan al elegir un [businessType].
///
/// ESPEJO del mapa `DefaultCapabilitiesForType` del backend
/// (internal/services/business_capabilities.go). El backend es la
/// fuente de verdad: aplica estos defaults al registrar el tenant. El
/// cliente solo usa este mapa para PRE-MARCAR el checklist del paso 2
/// del wizard de onboarding.
///
/// El mapa NO es un candado: cualquier tipo puede activar cualquier
/// capacidad luego desde "Capacidades del negocio" (spec §4.2).
///
/// Mapa (spec §4.2):
///   tienda_barrio / minimercado          → ninguna (solo core)
///   restaurante / comidas_rapidas        → recetas* + mesas + servicios
///   bar                                  → mesas + servicios
///   deposito_construccion                → cotizaciones + precios + clientes
///   manufactura / reparacion_muebles     → cotizaciones + clientes
///   emprendimiento_general               → clientes
///
/// (*) "recetas" no es una [OptionalCapability] toggleable — se activa
/// vía el `business_type` (capa byType del Dashboard), así que no
/// aparece en este set, que solo contiene capacidades con toggle.
Set<OptionalCapability> defaultCapabilitiesForType(String? businessType) {
  switch (businessType) {
    case 'restaurante':
    case 'comidas_rapidas':
      return const {
        OptionalCapability.tables,
        OptionalCapability.services,
      };
    case 'bar':
      return const {
        OptionalCapability.tables,
        OptionalCapability.services,
      };
    case 'deposito_construccion':
      return const {
        OptionalCapability.quotes,
        OptionalCapability.priceTiers,
        OptionalCapability.customerManagement,
      };
    case 'manufactura':
    case 'reparacion_muebles':
      return const {
        OptionalCapability.quotes,
        OptionalCapability.customerManagement,
      };
    case 'emprendimiento_general':
      return const {OptionalCapability.customerManagement};
    default: // tienda_barrio, minimercado, null
      return const {};
  }
}
