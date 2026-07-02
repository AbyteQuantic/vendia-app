// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Catálogo de metadata de cada capacidad opcional del negocio. Una sola
// fuente de verdad para el reel del Dashboard y las pantallas
// dedicadas. Cotizaciones tiene su pantalla propia
// (`QuoteCapabilityScreen`) porque expone settings funcionales; el
// resto se renderea con `CapabilityScaffold(metadata: ...)`.
//
// URLs Pexels — licencia libre para uso comercial sin atribución
// obligatoria. Si una URL no resuelve (cambia el ID en el CDN,
// offline al primer ingreso), el scaffold degrada al `fallbackIcon`
// del propio metadata. Cero crash, layout estable.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/business_capability_map.dart';
import '../customers/customers_list_screen.dart';
import '../inventory/ingredients_screen.dart';
import '../online_store/promo_management_screen.dart';
import '../promotions/promotions_list_screen.dart';
import '../purchases/purchase_orders_screen.dart';
import '../quotes/quotes_list_screen.dart';
import '../recipes/recipes_home_screen.dart';
import '../tables/tables_screen.dart';
import '../work_orders/work_orders_screen.dart';
import '../events/events_list_screen.dart';
import 'capability_scaffold.dart';

/// Catálogo inmutable de la metadata de cada capacidad. Las claves
/// `configKey` / `profileKey` deben coincidir con lo que el backend
/// espera en `PATCH /store/profile` y devuelve en `GET /store/profile`.
final Map<OptionalCapability, CapabilityMetadata> capabilitiesRegistry = {
  OptionalCapability.services: const CapabilityMetadata(
    title: 'Servicios',
    tagline: 'Cobre arreglos y trabajos por encargo',
    description:
        'Sume servicios al carrito junto a sus productos: cortes, '
        'instalaciones, reparaciones, mano de obra. Sin tocar el '
        'inventario.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/8005368/pexels-photo-8005368.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.handyman_rounded,
    accentColor: Color(0xFF7C3AED),
    configKey: 'offers_services',
    profileKey: 'enable_services',
    noModuleHint:
        'Después de activar, abra "Registrar venta" y verá la pestaña '
        'de servicios para agregarlos al cobro.',
  ),
  OptionalCapability.fractionalUnits: const CapabilityMetadata(
    title: 'Venta a granel',
    tagline: 'Venda por libra, kilo o litro',
    description:
        'Fraccione lo que vende: arroz por libra, aceite por litro, '
        'granos sueltos. El POS calcula el subtotal según la cantidad '
        'que pese o sirva.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/7937339/pexels-photo-7937339.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.scale_rounded,
    accentColor: Color(0xFFD97706),
    configKey: 'sells_by_weight',
    profileKey: 'enable_fractional_units',
    noModuleHint:
        'Al activar, los productos del inventario aceptarán cantidades '
        'decimales (1.5 kg, 0.25 lb) en "Registrar venta".',
  ),
  OptionalCapability.tables: const CapabilityMetadata(
    title: 'Atención en mesas',
    tagline: 'Maneje mesas y cuentas abiertas',
    description:
        'Para bares, restaurantes y salas de espera. Abra cuentas por '
        'mesa, agregue consumo durante la velada y cobre al final.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/941861/pexels-photo-941861.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.table_restaurant_rounded,
    accentColor: Color(0xFF3B82F6),
    configKey: 'has_tables',
    profileKey: 'enable_tables',
    primaryActionLabel: 'Ver mis mesas',
    primaryActionIcon: Icons.table_restaurant_rounded,
    primaryDestination: TablesScreen.new,
  ),
  OptionalCapability.priceTiers: const CapabilityMetadata(
    title: 'Precios mayorista y minorista',
    tagline: 'Dos o tres precios por producto',
    description:
        'Maneje precios distintos para cliente final, depósito o '
        'mayorista. Al cobrar, escoja el tipo de cliente y el POS '
        'aplica el precio correcto.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/4968638/pexels-photo-4968638.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.sell_rounded,
    accentColor: Color(0xFF059669),
    configKey: 'enable_price_tiers',
    profileKey: 'enable_price_tiers',
    noModuleHint:
        'Al activar, podrá poner precios por nivel en cada producto '
        '("Productos") y elegir el nivel al cobrar.',
  ),
  // Cotizaciones tiene su pantalla activadora propia (QuoteCapabilityScreen,
  // ruteada aparte en el reel). Pero SÍ necesita entrada en el registry para que
  // su card del carrusel tenga foto hero y botón "quitar" (onRemove depende de
  // capabilitiesRegistry[cap]); sin esto era la única capacidad no-removible y
  // sin foto (auditoría capacidades).
  OptionalCapability.quotes: const CapabilityMetadata(
    title: 'Cotizaciones',
    tagline: 'Arme cotizaciones y conviértalas en venta',
    description:
        'Cree cotizaciones para sus clientes con productos y precios, '
        'compártalas por WhatsApp y, cuando las aprueben, conviértalas '
        'en venta de un toque.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/4386366/pexels-photo-4386366.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.request_quote_rounded,
    accentColor: Color(0xFF1A2FA0),
    configKey: 'enable_quotes',
    profileKey: 'enable_quotes',
    primaryActionLabel: 'Ver mis cotizaciones',
    primaryActionIcon: Icons.request_quote_rounded,
    primaryDestination: QuotesListScreen.new,
  ),
  OptionalCapability.customerManagement: const CapabilityMetadata(
    title: 'Gestión de clientes',
    tagline: 'Sepa quién le compra y cuánto',
    description:
        'Registre a sus clientes, vea su historial de compras y total '
        'gastado. Indispensable si maneja fiado o si los clientes '
        'piden a domicilio.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/3760067/pexels-photo-3760067.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.people_outline,
    accentColor: Color(0xFF1A2FA0),
    configKey: 'enable_customer_management',
    profileKey: 'enable_customer_management',
    primaryActionLabel: 'Ver mis clientes',
    primaryActionIcon: Icons.people_alt_rounded,
    primaryDestination: CustomersListScreen.new,
  ),
  // Bug real reportado: esta pantalla y el módulo de combos
  // (marketingHub, abajo) se llamaban casi igual ("Mis promociones" /
  // "Mis Promociones") pese a ser features distintas — campañas de
  // WhatsApp vs. combos con descuento. Concilio (Workflow): esta es
  // "Anuncios", el módulo de combos se queda con la palabra "Combos"
  // siempre visible.
  OptionalCapability.promotions: const CapabilityMetadata(
    title: 'Anuncios por WhatsApp',
    tagline: 'Avise por WhatsApp cuando tenga ofertas',
    description:
        'Cree anuncios, banners y descuentos. Difúndalos por '
        'WhatsApp a sus clientes para llenar la tienda en días '
        'flojos.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/5632398/pexels-photo-5632398.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.campaign_rounded,
    accentColor: Color(0xFFD97706),
    configKey: 'enable_promotions',
    profileKey: 'enable_promotions',
    primaryActionLabel: 'Ver mis anuncios',
    primaryActionIcon: Icons.campaign_rounded,
    primaryDestination: PromotionsListScreen.new,
  ),
  OptionalCapability.marketingHub: const CapabilityMetadata(
    title: 'Combos y Promociones',
    tagline: 'Combos, banners con IA y catálogo en línea',
    description:
        'Arme combos a precio promocional, genere banners con IA y '
        'comparta su catálogo en línea por un enlace.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/267350/pexels-photo-267350.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.auto_awesome_rounded,
    accentColor: Color(0xFF7C3AED),
    configKey: 'enable_marketing_hub',
    profileKey: 'enable_marketing_hub',
    primaryActionLabel: 'Abrir Combos y Promociones',
    primaryActionIcon: Icons.auto_awesome_rounded,
    primaryDestination: PromoManagementScreen.new,
  ),
  OptionalCapability.recipes: const CapabilityMetadata(
    title: 'Recetas y Platos',
    tagline: 'Arme un plato y vea su costo y ganancia',
    description:
        'Defina los ingredientes de cada plato (almuerzos, bebidas, '
        'preparados). VendIA calcula el costo real y descuenta los '
        'insumos al vender.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/2284166/pexels-photo-2284166.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.restaurant_menu_rounded,
    accentColor: Color(0xFFEE5A24),
    configKey: 'enable_recipes',
    profileKey: 'enable_recipes',
    primaryActionLabel: 'Ver mis recetas',
    primaryActionIcon: Icons.restaurant_menu_rounded,
    // Abre el HOME del módulo (3 opciones: importar carta / crear / voz) +
    // lista de recetas, no el paso 1 del wizard directo (auditoría capacidades).
    primaryDestination: RecipesHomeScreen.new,
  ),
  OptionalCapability.supplies: const CapabilityMetadata(
    title: 'Mis Insumos',
    tagline: 'Materia prima: stock, mínimos y costo',
    description:
        'Registre la materia prima que usa: harina, gas, jabón, '
        'cualquier insumo. VendIA descuenta al vender una receta y '
        'avisa cuando esté bajo.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/1207978/pexels-photo-1207978.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.kitchen_rounded,
    accentColor: Color(0xFFD97706),
    configKey: 'enable_supplies',
    profileKey: 'enable_supplies',
    primaryActionLabel: 'Ver mis insumos',
    primaryActionIcon: Icons.kitchen_rounded,
    primaryDestination: IngredientsScreen.new,
  ),
  OptionalCapability.furnitureJobs: const CapabilityMetadata(
    title: 'Trabajos de Muebles',
    tagline: 'Cotice, fabrique y repare por encargo',
    description:
        'Para carpinteros, talleres y reparadores. Tome el pedido, '
        'cobre anticipo, mueva el estado del trabajo y entregue.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/3680219/pexels-photo-3680219.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.handyman_rounded,
    accentColor: AppTheme.primary,
    configKey: 'enable_furniture_jobs',
    profileKey: 'enable_furniture_jobs',
    primaryActionLabel: 'Ver mis trabajos',
    primaryActionIcon: Icons.handyman_rounded,
    primaryDestination: WorkOrdersScreen.new,
  ),
  OptionalCapability.purchaseOrders: const CapabilityMetadata(
    title: 'Órdenes de Compra',
    tagline: 'Pida a proveedores y reciba el stock',
    description:
        'Arme una orden con lo que va a comprar, envíela al proveedor '
        'por WhatsApp y cuando llegue la mercancía, súbala al '
        'inventario de un toque.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/4481259/pexels-photo-4481259.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.shopping_cart_rounded,
    accentColor: Color(0xFF0D9668),
    configKey: 'enable_purchase_orders',
    profileKey: 'enable_purchase_orders',
    primaryActionLabel: 'Ver mis órdenes',
    primaryActionIcon: Icons.shopping_cart_rounded,
    primaryDestination: PurchaseOrdersScreen.new,
  ),
  // F042 — Módulo de Eventos.
  OptionalCapability.events: const CapabilityMetadata(
    title: 'Eventos',
    tagline: 'Cobre cursos, conferencias y hackatones',
    description:
        'Cree eventos, véndalos en su catálogo, cobre la inscripción con '
        'sus propios métodos de pago (incluso a cuotas), entregue '
        'escarapelas y certificados, y controle la asistencia con QR.',
    heroPhotoUrl:
        'https://images.pexels.com/photos/2774556/pexels-photo-2774556.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop',
    fallbackIcon: Icons.event_rounded,
    accentColor: Color(0xFF0EA5E9),
    configKey: 'enable_events',
    profileKey: 'enable_events',
    primaryActionLabel: 'Ver mis eventos',
    primaryActionIcon: Icons.event_rounded,
    primaryDestination: EventsListScreen.new,
  ),
};
