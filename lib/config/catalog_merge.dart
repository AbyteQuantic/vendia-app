// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Construye la grilla y el reel del dashboard a partir del catálogo dinámico
// (F041), reutilizando el ícono y la pantalla compilados del bundle cuando
// el módulo ya existe en la app, y cayendo a `iconForKey` + pantalla genérica
// para módulos nuevos. La visibilidad replica el resolver del backend:
// override > requiere-Pro > inactivo-global > relación-por-tipo (implícito al
// grid; resto: en grid si la capacidad está activada, si no, descubrible).

import 'package:flutter/material.dart';

import '../models/catalog/catalog_models.dart';
import '../services/auth_service.dart' show FeatureFlags;
import '../theme/app_theme.dart';
import 'dashboard_modules.dart';
import 'module_icons.dart';
import 'screen_registry.dart';

class CatalogDashboard {
  final List<DashboardModule> grid;
  final List<DashboardModule> reel;
  const CatalogDashboard({required this.grid, required this.reel});
}

enum _Verdict { grid, reel, hidden }

/// Resuelve el dashboard desde el catálogo. [businessTypes] son los tipos del
/// tenant; [flags] sus capacidades activadas; [isPro] si tiene acceso Pro.
CatalogDashboard buildCatalogDashboard(
  Catalog catalog, {
  required List<String> businessTypes,
  required FeatureFlags flags,
  required bool isPro,
}) {
  final bundleById = {for (final m in dashboardModules) m.id: m};
  final overrideByModuleId = {
    for (final o in catalog.overrides) o.moduleId: o.forcedState,
  };
  final typeSet = businessTypes.toSet();

  final grid = <DashboardModule>[];
  final reel = <DashboardModule>[];
  for (final cm in catalog.modules) {
    switch (_resolve(cm, catalog.relations, overrideByModuleId, typeSet, flags, isPro)) {
      case _Verdict.grid:
        grid.add(_toModule(cm, bundleById));
      case _Verdict.reel:
        reel.add(_toModule(cm, bundleById));
      case _Verdict.hidden:
        break;
    }
  }
  return CatalogDashboard(grid: grid, reel: reel);
}

_Verdict _resolve(
  CatalogModule cm,
  List<CatalogRelation> relations,
  Map<String, String> overrides,
  Set<String> types,
  FeatureFlags flags,
  bool isPro,
) {
  final ov = overrides[cm.id];
  if (ov == 'active') return _Verdict.grid;
  if (ov == 'inactive') return _Verdict.hidden;
  if (cm.requiresPro && !isPro) return _Verdict.hidden;
  if (!cm.active) return _Verdict.hidden;

  final cap = cm.capabilityKey;
  if (cap == null || cap.isEmpty) return _Verdict.grid; // core

  for (final r in relations) {
    if (r.moduleId == cm.id &&
        r.relationLevel == 'implicit' &&
        types.contains(r.businessTypeValue)) {
      return _Verdict.grid; // implícito por tipo
    }
  }
  return _capEnabled(cap, flags) ? _Verdict.grid : _Verdict.reel;
}

DashboardModule _toModule(CatalogModule cm, Map<String, DashboardModule> bundleById) {
  final compiled = bundleById[cm.key];
  return DashboardModule(
    id: cm.key,
    title: cm.name,
    subtitle: cm.description,
    icon: compiled?.icon ?? iconForKey(cm.iconKey),
    color: _parseColor(cm.color) ?? compiled?.color ?? AppTheme.primary,
    category: _mapCategory(cm.category),
    layer: ModuleLayer.core,
    destination: compiled?.destination ?? (() => buildModuleScreen(cm)),
  );
}

bool _capEnabled(String key, FeatureFlags f) {
  switch (key) {
    case 'enable_quotes':
      return f.enableQuotes;
    case 'enable_supplies':
      return f.enableSupplies;
    case 'enable_recipes':
      return f.enableRecipes;
    case 'enable_purchase_orders':
      return f.enablePurchaseOrders;
    case 'enable_furniture_jobs':
      return f.enableFurnitureJobs;
    case 'enable_customer_management':
      return f.enableCustomerManagement;
    case 'enable_promotions':
      return f.enablePromotions;
    case 'enable_marketing_hub':
      return f.enableMarketingHub;
    case 'enable_price_tiers':
      return f.enablePriceTiers;
    case 'enable_services':
      return f.enableServices;
    case 'enable_tables':
      return f.enableTables;
    case 'enable_fractional_units':
      return f.enableFractionalUnits;
    default:
      return false;
  }
}

ModuleCategory _mapCategory(String c) {
  switch (c) {
    case 'inventario':
      return ModuleCategory.inventario;
    case 'clientes':
      return ModuleCategory.clientes;
    case 'mi_negocio':
      return ModuleCategory.miNegocio;
    case 'vender':
    default:
      return ModuleCategory.vender;
  }
}

Color? _parseColor(String hex) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.isEmpty) return null;
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
