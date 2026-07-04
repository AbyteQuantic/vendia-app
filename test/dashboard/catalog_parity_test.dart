// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Test de PARIDAD (AC-11): un catálogo que refleja el bundle compilado debe
// producir EXACTAMENTE los mismos módulos visibles que la lógica actual
// `visibleModulesFor`, para cualquier tipo de negocio y combinación de
// banderas. Es la compuerta antes de que el dashboard pase a leer el catálogo.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/catalog_merge.dart';
import 'package:vendia_pos/config/dashboard_modules.dart';
import 'package:vendia_pos/models/catalog/catalog_models.dart';
import 'package:vendia_pos/services/auth_service.dart' show FeatureFlags;
import 'package:vendia_pos/utils/business_capability_map.dart';

String? _capKey(OptionalCapability? c) {
  switch (c) {
    case OptionalCapability.quotes:
      return 'enable_quotes';
    case OptionalCapability.supplies:
      return 'enable_supplies';
    case OptionalCapability.recipes:
      return 'enable_recipes';
    case OptionalCapability.purchaseOrders:
      return 'enable_purchase_orders';
    case OptionalCapability.furnitureJobs:
      return 'enable_furniture_jobs';
    case OptionalCapability.customerManagement:
      return 'enable_customer_management';
    case OptionalCapability.promotions:
      return 'enable_promotions';
    case OptionalCapability.marketingHub:
      return 'enable_marketing_hub';
    case OptionalCapability.priceTiers:
      return 'enable_price_tiers';
    case OptionalCapability.services:
      return 'enable_services';
    case OptionalCapability.tables:
      return 'enable_tables';
    case OptionalCapability.fractionalUnits:
      return 'enable_fractional_units';
    case OptionalCapability.events:
      return 'enable_events';
    case OptionalCapability.staffCommissions:
      return 'enable_staff_commissions';
    case OptionalCapability.productVariants:
      return 'enable_product_variants';
    case null:
      return null;
  }
}

String _catStr(ModuleCategory c) => switch (c) {
      ModuleCategory.vender => 'vender',
      ModuleCategory.inventario => 'inventario',
      ModuleCategory.clientes => 'clientes',
      ModuleCategory.miNegocio => 'mi_negocio',
    };

/// Catálogo espejo del bundle compilado (lo que sembraría el backend).
Catalog _mirrorCatalog() {
  final modules = <CatalogModule>[];
  for (var i = 0; i < dashboardModules.length; i++) {
    final m = dashboardModules[i];
    modules.add(CatalogModule(
      id: m.id,
      key: m.id,
      name: m.title,
      description: m.subtitle,
      iconKey: '',
      color: '',
      category: _catStr(m.category),
      renderType: 'native',
      nativeScreenKey: m.id,
      webviewUrl: null,
      capabilityKey: _capKey(m.capability),
      requiresPro: false,
      active: true,
      sortOrder: i,
    ));
  }
  return Catalog(
    modules: modules,
    types: const [],
    relations: const [],
    overrides: const [],
    version: 'mirror',
  );
}

Set<String> _gridIds(List<DashboardModule> mods) => mods.map((m) => m.id).toSet();

void main() {
  final catalog = _mirrorCatalog();

  const businessTypes = [
    'tienda_barrio',
    'restaurante',
    'deposito_construccion',
    'reparacion_muebles',
  ];

  final flagSets = <String, FeatureFlags>{
    'todo apagado': const FeatureFlags(),
    'quotes on': const FeatureFlags(enableQuotes: true),
    'varias on': const FeatureFlags(
      enableQuotes: true,
      enableCustomerManagement: true,
      enableRecipes: true,
      enableMarketingHub: true,
    ),
    // F042 — eventos en grilla cuando enable_events está ON.
    'events on': const FeatureFlags(enableEvents: true),
  };

  // Regresión: el reel del catálogo debe conservar la `capability` de cada
  // card. Sin esto, tocar "Eventos" (y demás) caía a la pantalla general en
  // vez de su pantalla dedicada (_routeFor → capabilitiesRegistry[null]).
  test('reel del catálogo conserva la capability de cada card', () {
    final reel = buildCatalogDashboard(
      catalog,
      businessTypes: const ['tienda_barrio'],
      flags: const FeatureFlags(), // todo apagado → opcionales caen al reel
      isPro: true,
    ).reel;

    final events = reel.where((m) => m.capability == OptionalCapability.events);
    expect(events, isNotEmpty,
        reason: 'Eventos debe estar en el reel con su capability seteada');

    for (final m in reel) {
      expect(m.capability, isNotNull,
          reason: 'cada card opcional del reel necesita su capability para '
              'rutear a su pantalla dedicada');
    }
  });

  test('Spec 061: inyecta "catalogo_online" aunque el catálogo backend no lo traiga',
      () {
    // Simula el catálogo de prod, que todavía NO tiene el módulo
    // catalogo_online (es feature core de la app, no del catálogo F041).
    final sinCatalogo = catalog.modules
        .where((m) => m.key != 'catalogo_online')
        .toList();
    final cat = Catalog(
      modules: sinCatalogo,
      types: const [],
      relations: const [],
      overrides: const [],
      version: 'sin-catalogo-online',
    );

    final dash = buildCatalogDashboard(
      cat,
      businessTypes: const ['tienda_barrio'],
      flags: const FeatureFlags(),
      isPro: false,
    );

    expect(_gridIds(dash.grid), contains('catalogo_online'),
        reason: 'el botón verde debe aparecer aunque el catálogo no lo traiga');
  });

  for (final bt in businessTypes) {
    for (final entry in flagSets.entries) {
      test('paridad grilla — tipo=$bt, flags=${entry.key}', () {
        final expected = _gridIds(visibleModulesFor(bt, entry.value));
        final actual = _gridIds(
          buildCatalogDashboard(
            catalog,
            businessTypes: [bt],
            flags: entry.value,
            isPro: true,
          ).grid,
        );
        expect(actual, equals(expected),
            reason: 'el dashboard del catálogo debe igualar visibleModulesFor');
      });
    }
  }
}
