// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Registro de pantallas nativas: mapea el `native_screen_key` del catálogo
// dinámico a la pantalla Flutter COMPILADA correspondiente. Un módulo del
// catálogo cuyo render es `native` se abre con el builder de este mapa; si
// la clave no existe en la versión instalada, degrada a "próximamente"
// (FR-10/AC-09). `webview` y `placeholder` usan pantallas genéricas.

import 'package:flutter/material.dart';

import '../models/catalog/catalog_models.dart';
import '../screens/admin/suppliers_screen.dart';
import '../screens/customers/customers_list_screen.dart';
import '../screens/dashboard/admin_hub_screen.dart';
import '../screens/dashboard/financial_dashboard_screen.dart';
import '../screens/generic/module_placeholder_screen.dart';
import '../screens/generic/module_webview_screen.dart';
import '../screens/history/sales_history_screen.dart';
import '../screens/inventory/add_merchandise_screen.dart';
import '../screens/inventory/ingredients_screen.dart';
import '../screens/inventory/inventory_report_screen.dart';
import '../screens/online_store/promo_management_screen.dart';
import '../screens/pos/cuaderno_fiados_screen.dart';
import '../screens/pos/pos_screen.dart';
import '../screens/promotions/promotions_list_screen.dart';
import '../screens/purchases/purchase_orders_screen.dart';
import '../screens/quotes/quotes_list_screen.dart';
import '../screens/recipes/recipes_home_screen.dart';
import '../screens/work_orders/work_orders_screen.dart';
import '../screens/events/events_list_screen.dart';

typedef ScreenBuilder = Widget Function();

/// Claves estables → pantalla compilada. Sincronizar con los
/// `native_screen_key` del seed del backend (catalog_seed.go).
final Map<String, ScreenBuilder> kScreenRegistry = {
  'pos': PosScreen.new,
  'sales_history': SalesHistoryScreen.new,
  'financial_dashboard': FinancialDashboardScreen.new,
  'quotes': QuotesListScreen.new,
  'add_merchandise': AddMerchandiseScreen.new,
  'inventory_report': InventoryReportScreen.new,
  'suppliers': SuppliersScreen.new,
  'ingredients': IngredientsScreen.new,
  'recipes': RecipesHomeScreen.new,
  'purchase_orders': PurchaseOrdersScreen.new,
  'work_orders': WorkOrdersScreen.new,
  'customers': CustomersListScreen.new,
  'promotions': PromotionsListScreen.new,
  'promo_management': PromoManagementScreen.new,
  'admin_hub': AdminHubScreen.new,
  'eventos': EventsListScreen.new,
  // Cuaderno de fiados (ventas a crédito). Alias 'Creditos' porque el
  // fundador creó el módulo desde el admin con esa clave exacta antes de
  // que existiera el mapeo — sin el alias, su tile caía a "Próximamente".
  'creditos': CuadernoFiadosScreen.new,
  'Creditos': CuadernoFiadosScreen.new,
};

/// True si la app instalada conoce la pantalla nativa de [screenKey].
bool hasNativeScreen(String? screenKey) =>
    screenKey != null && kScreenRegistry.containsKey(screenKey);

/// Construye la pantalla destino de un módulo del catálogo según su
/// render_type, con degradación segura.
Widget buildModuleScreen(CatalogModule m) {
  switch (m.renderType) {
    case 'webview':
      return ModuleWebviewScreen(title: m.name, url: m.webviewUrl);
    case 'placeholder':
      return ModulePlaceholderScreen(title: m.name);
    case 'native':
    default:
      final builder = m.nativeScreenKey != null
          ? kScreenRegistry[m.nativeScreenKey]
          : null;
      if (builder != null) return builder();
      // Clave nativa desconocida en esta versión → no romper (FR-10).
      return ModulePlaceholderScreen(title: m.name);
  }
}
