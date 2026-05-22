// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
//
// T-20 — el registro declarativo de módulos cubre todos los módulos
// legacy del Dashboard, sin ids duplicados, cada uno con categoría,
// capa de visibilidad y destino navegable.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/dashboard_modules.dart';

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

    test('cubre todos los módulos legacy del Dashboard (AC-10)', () {
      // Cada módulo que hoy renderiza dashboard_screen.dart debe estar
      // representado en el registro — ninguno se pierde.
      const legacyIds = {
        'registrar_venta',
        'historial',
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

    test('las 4 categorías tienen al menos un módulo', () {
      for (final cat in ModuleCategory.values) {
        expect(dashboardModules.any((m) => m.category == cat), isTrue,
            reason: 'la categoría $cat no tiene módulos');
      }
    });
  });
}
