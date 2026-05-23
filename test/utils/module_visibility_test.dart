// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
//
// T-22 — filtrado por capa de visibilidad:
//   core     → siempre visible
//   byType   → visible solo si el business_type matchea
//   optional → visible solo si la capacidad (feature flag) está ON

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/dashboard_modules.dart';
import 'package:vendia_pos/services/auth_service.dart';

void main() {
  group('visibleModulesFor', () {
    test('core siempre visible para cualquier tipo', () {
      final coreIds = dashboardModules
          .where((m) => m.layer == ModuleLayer.core)
          .map((m) => m.id)
          .toSet();
      final visible = visibleModulesFor('tienda_barrio', const FeatureFlags())
          .map((m) => m.id)
          .toSet();
      expect(visible.containsAll(coreIds), isTrue);
    });

    test('tienda_barrio sin capacidades ve SOLO los módulos core (AC-03)', () {
      final visible =
          visibleModulesFor('tienda_barrio', const FeatureFlags());
      for (final m in visible) {
        expect(m.layer, ModuleLayer.core,
            reason: 'tienda_barrio no debería ver ${m.id} (${m.layer})');
      }
      // No ve módulos especializados.
      final ids = visible.map((m) => m.id).toSet();
      expect(ids, isNot(contains('recetas')));
      expect(ids, isNot(contains('trabajos_muebles')));
      expect(ids, isNot(contains('cotizaciones')));
      expect(ids, isNot(contains('promociones')));
      expect(ids, isNot(contains('mis_clientes')));
    });

    test(
        'F037: reparacion_muebles SIN enableFurnitureJobs NO ve Trabajos de Muebles',
        () {
      // F037 migró "trabajos_muebles" de byType a optional con
      // capacidad propia (enableFurnitureJobs). El tipo de negocio ya
      // no lo activa solo; el backfill backend prende la flag para
      // tenants con datos en `work_orders`. Sin la flag y sin datos
      // el módulo NO aparece.
      final ids = visibleModulesFor('reparacion_muebles', const FeatureFlags())
          .map((m) => m.id)
          .toSet();
      expect(ids, isNot(contains('trabajos_muebles')));
    });

    test('F037: con enableFurnitureJobs=true → Trabajos de Muebles aparece',
        () {
      final ids = visibleModulesFor(
        'reparacion_muebles',
        const FeatureFlags(enableFurnitureJobs: true),
      ).map((m) => m.id).toSet();
      expect(ids, contains('trabajos_muebles'));
    });

    test('F037: restaurante SIN enableRecipes NO ve Recetas', () {
      // Idem: "recetas" migró a optional con enableRecipes (backfill
      // prende la flag para tenants con filas en `recipes`).
      final ids = visibleModulesFor('restaurante', const FeatureFlags())
          .map((m) => m.id)
          .toSet();
      expect(ids, isNot(contains('recetas')));
    });

    test('F037: con enableRecipes=true → Recetas aparece', () {
      final ids = visibleModulesFor(
        'restaurante',
        const FeatureFlags(enableRecipes: true),
      ).map((m) => m.id).toSet();
      expect(ids, contains('recetas'));
    });

    test('tienda_barrio NO ve Recetas (byType de restaurante)', () {
      final ids = visibleModulesFor('tienda_barrio', const FeatureFlags())
          .map((m) => m.id)
          .toSet();
      expect(ids, isNot(contains('recetas')));
    });

    test('módulo optional aparece cuando la capacidad está ON', () {
      const flags = FeatureFlags(enableCustomerManagement: true);
      final ids = visibleModulesFor('tienda_barrio', flags)
          .map((m) => m.id)
          .toSet();
      expect(ids, contains('mis_clientes'),
          reason: 'Mis Clientes aparece al prender enable_customer_management');
    });

    test('módulo optional NO aparece cuando la capacidad está OFF', () {
      final ids = visibleModulesFor('tienda_barrio', const FeatureFlags())
          .map((m) => m.id)
          .toSet();
      expect(ids, isNot(contains('cotizaciones')));
      expect(ids, isNot(contains('promociones')));
    });

    test('cualquier tipo puede activar cualquier capacidad opcional (AC-06)', () {
      // Una tienda de barrio con la capacidad de cotizaciones ON sí la ve.
      const flags = FeatureFlags(enableQuotes: true);
      final ids = visibleModulesFor('tienda_barrio', flags)
          .map((m) => m.id)
          .toSet();
      expect(ids, contains('cotizaciones'));
    });

    test('businessType null no rompe — devuelve al menos los core', () {
      final ids = visibleModulesFor(null, const FeatureFlags())
          .map((m) => m.id)
          .toSet();
      final coreIds = dashboardModules
          .where((m) => m.layer == ModuleLayer.core)
          .map((m) => m.id)
          .toSet();
      expect(ids.containsAll(coreIds), isTrue);
    });
  });
}
