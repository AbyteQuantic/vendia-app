// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// Registro declarativo de los módulos del Dashboard — una sola fuente
// de verdad. El Dashboard (dashboard_screen.dart) se construye iterando
// `dashboardModules` y filtrando con `visibleModulesFor(...)`.
//
// Cada módulo declara:
//   - categoría     → en cuál de las 4 secciones se agrupa
//   - capa          → core / byType / optional (regla de visibilidad)
//   - destino       → builder de la pantalla a la que navega
//
// Capas de visibilidad (spec §4.1):
//   core     → visible para todos los negocios.
//   byType   → visible si `business_type` está en `businessTypes`.
//   optional → visible si la `capability` correspondiente está ON.
//
// F037 cambió la filosofía de F036:
//   - Default ultra-simple: SOLO 5 cores arrancan visibles para todos:
//     registrar_venta, historial, analisis_ganancias, productos,
//     configuracion. (Reporte de inventario y proveedores quedan también
//     como core porque son útiles a cualquier tipo de negocio.)
//   - Marketing Hub deja de ser core y se vuelve opt-in via
//     `enable_marketing_hub`.
//   - Cotizaciones / Clientes / Promociones siguen siendo opt-in.
//   - Recetas / Insumos / Trabajos / Órdenes siguen siendo byType
//     (mientras el backend no exponga una capacidad propia para cada
//     uno — ver decisión en el reporte de cierre de F037).
//
// Para sumar un módulo nuevo: agregar una entrada acá. El Dashboard,
// los tests de cobertura (AC-10) y el filtrado lo recogen solos.

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/business_capability_map.dart';
import '../screens/admin/suppliers_screen.dart';
import '../screens/customers/customers_list_screen.dart';
import '../screens/dashboard/admin_hub_screen.dart';
import '../screens/dashboard/financial_dashboard_screen.dart';
import '../screens/history/sales_history_screen.dart';
import '../screens/inventory/add_merchandise_screen.dart';
import '../screens/inventory/ingredients_screen.dart';
import '../screens/inventory/inventory_report_screen.dart';
import '../screens/online_store/catalog_online_hub_screen.dart';
import '../screens/online_store/promo_management_screen.dart';
import '../screens/pos/pos_screen.dart';
import '../screens/promotions/promotions_list_screen.dart';
import '../screens/purchases/purchase_orders_screen.dart';
import '../screens/quotes/quotes_list_screen.dart';
import '../screens/recipes/recipes_home_screen.dart';
import '../screens/work_orders/work_orders_screen.dart';
import '../screens/capabilities/capabilities_registry.dart';
import '../screens/capabilities/capability_scaffold.dart';
import '../screens/events/events_list_screen.dart';
import '../screens/staff/agenda_screen.dart';
import '../screens/staff/liquidations_screen.dart';
import '../screens/kds/comandas_screen.dart';
import '../screens/tables/tables_screen.dart';

/// Las 4 categorías con encabezado del Dashboard (spec §4.1).
enum ModuleCategory { vender, inventario, clientes, miNegocio }

/// Capa de visibilidad de un módulo.
enum ModuleLayer {
  /// Visible para todos los negocios.
  core,

  /// Visible solo si `business_type` está en `businessTypes`.
  byType,

  /// Visible solo si la `capability` (feature flag) está ON.
  optional,
}

/// Encabezado en español de cada categoría.
extension ModuleCategoryLabel on ModuleCategory {
  String get label => switch (this) {
        ModuleCategory.vender => 'VENDER',
        ModuleCategory.inventario => 'INVENTARIO',
        ModuleCategory.clientes => 'CLIENTES',
        ModuleCategory.miNegocio => 'MI NEGOCIO',
      };
}

/// Un módulo del Dashboard. Inmutable — el registro es `const`.
class DashboardModule {
  /// Identificador estable (usado en tests y como Key del widget).
  final String id;

  /// Título visible en la tarjeta.
  final String title;

  /// Subtítulo / descripción corta.
  final String subtitle;

  /// Ícono de la tarjeta.
  final IconData icon;

  /// Color de acento de la tarjeta.
  final Color color;

  /// Categoría con encabezado donde se agrupa.
  final ModuleCategory category;

  /// Capa de visibilidad.
  final ModuleLayer layer;

  /// Builder de la pantalla destino.
  final Widget Function() destination;

  /// Para [ModuleLayer.byType]: tipos de negocio que activan el módulo.
  /// Vacío para core/optional.
  final List<String> businessTypes;

  /// Para [ModuleLayer.optional]: capacidad que gatea el módulo.
  /// `null` para core/byType.
  final OptionalCapability? capability;

  const DashboardModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.category,
    required this.layer,
    required this.destination,
    this.businessTypes = const [],
    this.capability,
  });
}

// F037: Insumos/Recetas/Órdenes/Trabajos migraron de byType a opcional;
// las listas de tipos por defecto se eliminaron — la activación corre
// por capacidades + backfill backend para tenants con data legacy.

/// Registro central de todos los módulos del Dashboard.
// Destinos de las capacidades de COMPORTAMIENTO (sin pantalla-módulo propia):
// abren su CapabilityScaffold (estado activo + cómo usar + apagar). Son
// funciones top-level para que su tear-off sea const y la lista siga siendo const.
Widget _priceTiersModule() =>
    CapabilityScaffold(metadata: capabilitiesRegistry[OptionalCapability.priceTiers]!);
Widget _servicesModule() =>
    CapabilityScaffold(metadata: capabilitiesRegistry[OptionalCapability.services]!);
Widget _fractionalModule() =>
    CapabilityScaffold(metadata: capabilitiesRegistry[OptionalCapability.fractionalUnits]!);

const List<DashboardModule> dashboardModules = [
  // ── VENDER ───────────────────────────────────────────────────────
  DashboardModule(
    id: 'registrar_venta',
    title: 'Registrar venta',
    subtitle: 'Cobre rápido y registre el pago',
    icon: Icons.point_of_sale_rounded,
    color: AppTheme.primary,
    category: ModuleCategory.vender,
    layer: ModuleLayer.core,
    destination: PosScreen.new,
  ),
  // Botón destacado VERDE bajo "Registrar venta": reúne el catálogo en
  // línea (vista previa, compartir/copiar link, campañas masivas, banner).
  DashboardModule(
    id: 'catalogo_online',
    title: 'Catálogo Online',
    subtitle: 'Active, personalice y comparta su tienda en línea',
    icon: Icons.storefront_rounded,
    color: AppTheme.success,
    category: ModuleCategory.vender,
    layer: ModuleLayer.core,
    destination: CatalogOnlineHubScreen.new,
  ),
  DashboardModule(
    id: 'historial',
    title: 'Historial de ventas',
    subtitle: 'Vea todas las ventas registradas',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFF3B82F6),
    category: ModuleCategory.vender,
    layer: ModuleLayer.core,
    destination: SalesHistoryScreen.new,
  ),
  // F037: "Análisis de Ganancias" se promociona a core en VENDER.
  // Antes vivía suelto como un botón del Dashboard; ahora es una card
  // permanente para que el dueño revise utilidad sin cazarla.
  DashboardModule(
    id: 'analisis_ganancias',
    title: 'Análisis de Ganancias',
    subtitle: 'Utilidad, márgenes e ingresos por método',
    icon: Icons.bar_chart_rounded,
    color: Color(0xFF059669),
    category: ModuleCategory.vender,
    layer: ModuleLayer.core,
    destination: FinancialDashboardScreen.new,
  ),
  DashboardModule(
    id: 'cotizaciones',
    title: 'Cotizaciones',
    subtitle: 'Arme y envíe propuestas de precio',
    icon: Icons.description_outlined,
    color: Color(0xFF1A2FA0),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.quotes,
    destination: QuotesListScreen.new,
  ),

  // ── INVENTARIO ───────────────────────────────────────────────────
  DashboardModule(
    id: 'productos',
    title: 'Productos',
    subtitle: 'Agregue mercancía, edite precios y stock',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFF6366F1),
    category: ModuleCategory.inventario,
    layer: ModuleLayer.core,
    destination: AddMerchandiseScreen.new,
  ),
  DashboardModule(
    id: 'reporte_inventario',
    title: 'Reporte de Inventario',
    subtitle: 'Kardex, entradas, salidas y stock',
    icon: Icons.assessment_rounded,
    color: Color(0xFF059669),
    category: ModuleCategory.inventario,
    layer: ModuleLayer.core,
    destination: InventoryReportScreen.new,
  ),
  DashboardModule(
    id: 'proveedores',
    title: 'Mis Proveedores',
    subtitle: 'Pedidos por WhatsApp, llamada o SMS',
    icon: Icons.local_shipping_rounded,
    color: Color(0xFF764BA2),
    category: ModuleCategory.inventario,
    layer: ModuleLayer.core,
    destination: SuppliersScreen.new,
  ),
  // F037 — los 4 módulos siguientes migraron de byType a optional.
  // El backend agregó columnas dedicadas (enable_recipes / enable_supplies
  // / enable_furniture_jobs / enable_purchase_orders) + backfill para
  // tenants que ya tenían datos en cada tabla legacy. Cualquier negocio
  // (no solo cooking/furniture) puede activarlos desde el reel.
  DashboardModule(
    id: 'insumos',
    title: 'Mis Insumos',
    subtitle: 'Materia prima: stock, mínimos y costo',
    icon: Icons.kitchen_rounded,
    color: Color(0xFFD97706),
    category: ModuleCategory.inventario,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.supplies,
    destination: IngredientsScreen.new,
  ),
  DashboardModule(
    id: 'recetas',
    title: 'Recetas y Platos',
    subtitle: 'Arme un plato y vea su costo y ganancia',
    icon: Icons.restaurant_menu_rounded,
    color: Color(0xFFEE5A24),
    category: ModuleCategory.inventario,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.recipes,
    // F043: el módulo abre la pantalla de 3 opciones (importar menú con cámara,
    // crear plato/receta, dictar por voz) en vez del formulario manual directo.
    destination: RecipesHomeScreen.new,
  ),
  DashboardModule(
    id: 'ordenes_compra',
    title: 'Órdenes de Compra',
    subtitle: 'Pida a proveedores y reciba el stock',
    icon: Icons.shopping_cart_rounded,
    color: Color(0xFF0D9668),
    category: ModuleCategory.inventario,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.purchaseOrders,
    destination: PurchaseOrdersScreen.new,
  ),
  DashboardModule(
    id: 'trabajos_muebles',
    title: 'Trabajos de Muebles',
    subtitle: 'Cotice, fabrique y repare por encargo',
    icon: Icons.handyman_rounded,
    color: AppTheme.primary,
    category: ModuleCategory.inventario,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.furnitureJobs,
    destination: WorkOrdersScreen.new,
  ),

  // ── CLIENTES ─────────────────────────────────────────────────────
  DashboardModule(
    id: 'mis_clientes',
    title: 'Mis Clientes',
    subtitle: 'Quién le compra: historial y total gastado',
    icon: Icons.people_outline,
    color: Color(0xFF1A2FA0),
    category: ModuleCategory.clientes,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.customerManagement,
    destination: CustomersListScreen.new,
  ),
  // Bug real reportado: este tile y "marketing_hub" (abajo) se llamaban
  // casi igual ("Promociones" / "Marketing y Combos" → adentro ambos decían
  // "Mis Promociones") pese a ser features distintas — campañas de
  // WhatsApp vs. combos con descuento. Concilio (Workflow): este es
  // "Anuncios", el otro se queda con "Combos" siempre visible.
  DashboardModule(
    id: 'promociones',
    title: 'Anuncios por WhatsApp',
    subtitle: 'Avísele a sus clientes cuando tenga ofertas',
    icon: Icons.campaign_rounded,
    color: Color(0xFFD97706),
    category: ModuleCategory.clientes,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.promotions,
    destination: PromotionsListScreen.new,
  ),
  // Spec 105 F2 — KDS de cocina: comandas vivas para restaurante/comidas
  // rápidas/bar (implícito por tipo en el catálogo F041; descubrible vía
  // capacidad de mesas para el resto).
  DashboardModule(
    id: 'comandas',
    title: 'Comandas de Cocina',
    subtitle: 'Pedidos en vivo: prepare, marque listo y entregue',
    icon: Icons.soup_kitchen_rounded,
    color: Color(0xFFEA580C),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.tables,
    destination: ComandasScreen.new,
  ),
  // F042 — Módulo de Eventos. Opt-in self-service desde el reel.
  DashboardModule(
    id: 'mesas',
    title: 'Atención en mesas',
    subtitle: 'Abra cuentas por mesa y cobre al final',
    icon: Icons.table_restaurant_rounded,
    color: Color(0xFF3B82F6),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.tables,
    // Faltaba registrar el módulo: enable_tables persistía pero "Mesas" nunca
    // subía al carrusel/grid (auditoría capacidades). Ahora aparece como activo.
    destination: TablesScreen.new,
  ),
  // Capacidades de COMPORTAMIENTO (precios por nivel, servicios, granel): no
  // tienen pantalla-módulo propia (modifican el POS / los productos). Antes, al
  // activarlas, NO aparecían en el carrusel (no había DashboardModule) — el
  // usuario las prendía y "desaparecían". Ahora se registran apuntando a su
  // CapabilityScaffold, que muestra el estado activo + cómo usarlas + apagar.
  DashboardModule(
    id: 'precios_nivel',
    title: 'Precios mayorista y minorista',
    subtitle: 'Dos o tres precios por producto',
    icon: Icons.sell_rounded,
    color: Color(0xFF059669),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.priceTiers,
    destination: _priceTiersModule,
  ),
  DashboardModule(
    id: 'servicios',
    title: 'Servicios',
    subtitle: 'Cobre arreglos y trabajos por encargo',
    icon: Icons.handyman_rounded,
    color: Color(0xFF7C3AED),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.services,
    destination: _servicesModule,
  ),
  DashboardModule(
    id: 'granel',
    title: 'Venta a granel',
    subtitle: 'Venda por libra, kilo o litro',
    icon: Icons.scale_rounded,
    color: Color(0xFFD97706),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.fractionalUnits,
    destination: _fractionalModule,
  ),
  DashboardModule(
    id: 'eventos',
    title: 'Eventos',
    subtitle: 'Cobre cursos, conferencias y hackatones; entregue escarapelas',
    icon: Icons.event_rounded,
    color: Color(0xFF0EA5E9),
    category: ModuleCategory.clientes,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.events,
    destination: EventsListScreen.new,
  ),

  // ── MI NEGOCIO ───────────────────────────────────────────────────
  // F037: Marketing Hub deja de ser core. Aparece en el reel como
  // capacidad descubrible y solo se renderiza acá si
  // `enable_marketing_hub` está ON (backfill lo prende para tenants
  // que ya usaban combos/banners).
  DashboardModule(
    id: 'marketing_hub',
    title: 'Combos y Promociones',
    subtitle: 'Combos, banners con IA y catálogo en línea',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF7C3AED),
    category: ModuleCategory.miNegocio,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.marketingHub,
    destination: PromoManagementScreen.new,
  ),
  // Spec 084 Fase 2 — agenda de turnos/citas (peluquería/barbería).
  DashboardModule(
    id: 'agenda_turnos',
    title: 'Agenda de turnos',
    subtitle: 'Citas reservadas por sus clientes en línea',
    icon: Icons.event_available_rounded,
    color: Color(0xFF0EA5E9),
    category: ModuleCategory.vender,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.staffCommissions,
    destination: AgendaScreen.new,
  ),
  // Spec 084 — peluquería/barbería: liquidación a profesionales.
  DashboardModule(
    id: 'liquidaciones',
    title: 'Liquidaciones',
    subtitle: 'Comisiones, arriendo de silla y pagos a profesionales',
    icon: Icons.content_cut_rounded,
    color: Color(0xFF10B981),
    category: ModuleCategory.miNegocio,
    layer: ModuleLayer.optional,
    capability: OptionalCapability.staffCommissions,
    destination: LiquidationsScreen.new,
  ),
  DashboardModule(
    id: 'configuracion',
    title: 'Ajustes de mi Negocio',
    subtitle: 'Perfil, capacidades, empleados y dispositivos',
    icon: Icons.settings_rounded,
    color: Color(0xFF1E3A8A),
    category: ModuleCategory.miNegocio,
    layer: ModuleLayer.core,
    destination: AdminHubScreen.new,
  ),
];

/// Filtra el registro según el [businessType] y los [flags] del tenant.
///
/// Reglas (spec §4.1):
///   - core     → siempre incluido.
///   - byType   → incluido si `businessType` está en `module.businessTypes`.
///   - optional → incluido si la `capability` correspondiente está ON.
List<DashboardModule> visibleModulesFor(
  String? businessType,
  FeatureFlags flags,
) {
  return dashboardModules.where((m) {
    switch (m.layer) {
      case ModuleLayer.core:
        return true;
      case ModuleLayer.byType:
        return businessType != null &&
            m.businessTypes.contains(businessType);
      case ModuleLayer.optional:
        return capabilityEnabled(m.capability, flags);
    }
  }).toList();
}

/// Capacidades opcionales DEL REGISTRO (módulos con `layer == optional`)
/// que aún NO están activas en los [flags] del tenant.
///
/// El reel del Dashboard (F037) renderea una card por cada uno de éstos
/// para que el dueño los descubra y los active de un toque. Si la lista
/// queda vacía el reel se oculta (AC-07).
List<DashboardModule> unactivatedOptionalModules(FeatureFlags flags) {
  return dashboardModules
      .where((m) =>
          m.layer == ModuleLayer.optional &&
          m.capability != null &&
          !capabilityEnabled(m.capability, flags))
      .toList();
}

/// Mapea una [OptionalCapability] al flag correspondiente de [FeatureFlags].
///
/// Expuesto (no privado) porque el reel del Dashboard (F037) lo usa para
/// filtrar las cards a renderear sin duplicar la lógica.
bool capabilityEnabled(OptionalCapability? cap, FeatureFlags flags) {
  return switch (cap) {
    OptionalCapability.services => flags.enableServices,
    OptionalCapability.fractionalUnits => flags.enableFractionalUnits,
    OptionalCapability.tables => flags.enableTables,
    OptionalCapability.priceTiers => flags.enablePriceTiers,
    OptionalCapability.customerManagement => flags.enableCustomerManagement,
    OptionalCapability.quotes => flags.enableQuotes,
    OptionalCapability.promotions => flags.enablePromotions,
    OptionalCapability.marketingHub => flags.enableMarketingHub,
    // F037: módulos byType → opcional con backfill.
    OptionalCapability.recipes => flags.enableRecipes,
    OptionalCapability.supplies => flags.enableSupplies,
    OptionalCapability.furnitureJobs => flags.enableFurnitureJobs,
    OptionalCapability.purchaseOrders => flags.enablePurchaseOrders,
    OptionalCapability.events => flags.enableEvents,
    OptionalCapability.staffCommissions => flags.enableStaffCommissions,
    // Spec 095 — no tiene card en el reel (se activa desde Capacidades del
    // negocio), pero el switch debe ser exhaustivo.
    OptionalCapability.productVariants => flags.enableProductVariants,
    null => false,
  };
}

/// Mapea la `capability_key` del catálogo dinámico (F041, p. ej.
/// 'enable_events') a su [OptionalCapability]. Inverso de la metadata de cada
/// módulo. Lo usa `catalog_merge` para poblar `DashboardModule.capability` en
/// el camino del catálogo — sin esto, el reel pierde la capacidad y tocar una
/// card cae a la pantalla general en vez de su pantalla dedicada.
OptionalCapability? capabilityFromConfigKey(String? key) {
  return switch (key) {
    'enable_services' => OptionalCapability.services,
    'enable_fractional_units' => OptionalCapability.fractionalUnits,
    'enable_tables' => OptionalCapability.tables,
    'enable_price_tiers' => OptionalCapability.priceTiers,
    'enable_customer_management' => OptionalCapability.customerManagement,
    'enable_quotes' => OptionalCapability.quotes,
    'enable_promotions' => OptionalCapability.promotions,
    'enable_marketing_hub' => OptionalCapability.marketingHub,
    'enable_recipes' => OptionalCapability.recipes,
    'enable_supplies' => OptionalCapability.supplies,
    'enable_furniture_jobs' => OptionalCapability.furnitureJobs,
    'enable_purchase_orders' => OptionalCapability.purchaseOrders,
    'enable_events' => OptionalCapability.events,
    'enable_staff_commissions' => OptionalCapability.staffCommissions,
    _ => null,
  };
}
