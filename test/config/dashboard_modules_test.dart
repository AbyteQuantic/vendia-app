// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// T-22 — el registro declarativo de módulos cubre todos los módulos
// legacy del Dashboard, sin ids duplicados, cada uno con categoría,
// capa de visibilidad y destino navegable. F037 reduce los cores al
// mínimo: solo registrar_venta, historial, analisis_ganancias,
// productos, configuracion (+ reporte_inventario y proveedores
// quedan como core porque sirven a cualquier negocio). El resto es
// opcional con `capability != null` o byType.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/dashboard_modules.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/utils/business_capability_map.dart';

void main() {
  group('dashboardModules registry', () {
    test('no tiene ids duplicados', () {
      final ids = dashboardModules.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'cada DashboardModule debe tener un id único');
    });

    test('cada módulo tiene título, categoría, capa y destino', () {
      for (final m in dashboardModules) {
        expect(m.title.trim(), isNotEmpty, reason: 'id ${m.id} sin título');
        expect(m.category, isA<ModuleCategory>());
        expect(m.layer, isA<ModuleLayer>());
        final dest = m.destination();
        expect(dest, isA<Widget>(),
            reason: 'id ${m.id} debe devolver un Widget navegable');
      }
    });

    test('cubre todos los módulos legacy del Dashboard (AC-02)', () {
      // Cada módulo que hoy renderiza dashboard_screen.dart debe estar
      // representado en el registro — ninguno se pierde. F037 agrega
      // analisis_ganancias como core.
      const legacyIds = {
        'registrar_venta',
        'historial',
        'analisis_ganancias',
        'productos',
        'reporte_inventario',
        'proveedores',
        'ordenes_compra',
        'insumos',
        'recetas',
        'trabajos_muebles',
        'mis_clientes',
        'cotizaciones',
        'promociones',
        'marketing_hub',
        'configuracion',
      };
      final registryIds = dashboardModules.map((m) => m.id).toSet();
      for (final id in legacyIds) {
        expect(registryIds, contains(id),
            reason: 'módulo legacy "$id" ausente del registro');
      }
    });

    test('F037: los cores reducidos son solo los esenciales', () {
      // El default ultra-simple (spec §4.1): pocos cores. Aceptamos
      // 5–7 cores: los 5 nominados + reporte_inventario y proveedores
      // que también arrancan visibles porque son útiles a todo tipo.
      final cores = dashboardModules
          .where((m) => m.layer == ModuleLayer.core)
          .map((m) => m.id)
          .toSet();
      expect(cores.length, greaterThanOrEqualTo(5));
      expect(cores.length, lessThanOrEqualTo(7));
      expect(cores, contains('registrar_venta'));
      expect(cores, contains('historial'));
      expect(cores, contains('analisis_ganancias'));
      expect(cores, contains('productos'));
      expect(cores, contains('configuracion'));
    });

    test('F037: marketing_hub NO es core (es opt-in)', () {
      final marketing =
          dashboardModules.firstWhere((m) => m.id == 'marketing_hub');
      expect(marketing.layer, ModuleLayer.optional,
          reason:
              'F037 movió Marketing Hub a opt-in con capacidad propia');
      expect(marketing.capability, OptionalCapability.marketingHub);
    });

    test('F037: analisis_ganancias en categoría VENDER y como core', () {
      final analisis =
          dashboardModules.firstWhere((m) => m.id == 'analisis_ganancias');
      expect(analisis.layer, ModuleLayer.core);
      expect(analisis.category, ModuleCategory.vender);
    });

    test('los módulos byType declaran businessTypes', () {
      for (final m in dashboardModules.where(
          (m) => m.layer == ModuleLayer.byType)) {
        expect(m.businessTypes, isNotEmpty,
            reason: 'módulo byType ${m.id} debe declarar businessTypes');
      }
    });

    test('los módulos optional declaran una capability', () {
      for (final m in dashboardModules.where(
          (m) => m.layer == ModuleLayer.optional)) {
        expect(m.capability, isNotNull,
            reason: 'módulo optional ${m.id} debe declarar capability');
      }
    });

    test('los módulos core NO declaran businessTypes ni capability', () {
      for (final m in dashboardModules.where(
          (m) => m.layer == ModuleLayer.core)) {
        expect(m.businessTypes, isEmpty);
        expect(m.capability, isNull);
      }
    });

    test('"registrar_venta" es core y está en categoría vender', () {
      final sale = dashboardModules.firstWhere(
          (m) => m.id == 'registrar_venta');
      expect(sale.layer, ModuleLayer.core);
      expect(sale.category, ModuleCategory.vender);
    });

    test('al menos 3 de las 4 categorías tienen un módulo core', () {
      // F037: CLIENTES queda sin cores (mis_clientes + promociones son
      // opt-in y solo aparecen tras activar su capacidad). El resto de
      // categorías (VENDER, INVENTARIO, MI NEGOCIO) siempre tienen al
      // menos un core para que el Dashboard nunca quede vacío al
      // arrancar un negocio nuevo.
      final coresByCategory = <ModuleCategory, int>{};
      for (final m in dashboardModules
          .where((m) => m.layer == ModuleLayer.core)) {
        coresByCategory.update(m.category, (v) => v + 1,
            ifAbsent: () => 1);
      }
      expect((coresByCategory[ModuleCategory.vender] ?? 0),
          greaterThanOrEqualTo(1));
      expect((coresByCategory[ModuleCategory.inventario] ?? 0),
          greaterThanOrEqualTo(1));
      expect((coresByCategory[ModuleCategory.miNegocio] ?? 0),
          greaterThanOrEqualTo(1));
    });
  });

  group('unactivatedOptionalModules', () {
    test('sin flags devuelve TODAS las opcionales del registro', () {
      const flags = FeatureFlags();
      final unactivated = unactivatedOptionalModules(flags);
      final optionalIds = dashboardModules
          .where((m) => m.layer == ModuleLayer.optional)
          .map((m) => m.id)
          .toSet();
      expect(unactivated.map((m) => m.id).toSet(), optionalIds);
    });

    test('al activar enable_customer_management quita "mis_clientes"', () {
      const flags = FeatureFlags(enableCustomerManagement: true);
      final unactivated = unactivatedOptionalModules(flags);
      expect(
          unactivated.where((m) => m.id == 'mis_clientes').isEmpty, isTrue);
      // Las demás opcionales siguen ahí.
      expect(unactivated.map((m) => m.id), contains('marketing_hub'));
    });

    test('con TODAS las opcionales ON devuelve vacío (AC-07)', () {
      const flags = FeatureFlags(
        enableServices: true,
        enableFractionalUnits: true,
        enableTables: true,
        enablePriceTiers: true,
        enableCustomerManagement: true,
        enableQuotes: true,
        enablePromotions: true,
        enableMarketingHub: true,
      );
      final unactivated = unactivatedOptionalModules(flags);
      expect(unactivated, isEmpty);
    });
  });
}
