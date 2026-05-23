// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// T-27 — widget test del grid adaptativo del Dashboard:
//   - "Registrar venta" presente y destacado al inicio de VENDER.
//   - "Análisis de Ganancias" presente como core (F037).
//   - una tienda_barrio NO muestra Recetas / Mesas / Trabajos /
//     Cotizaciones / Promociones / Clientes / Marketing Hub (AC-03).
//   - probado a 360dp de ancho (Gerontodiseño, AC-12).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/dashboard_module_grid.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(360, 1200)),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  group('DashboardModuleGrid', () {
    testWidgets('renderea las categorías con módulos visibles',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'reparacion_muebles',
          flags: FeatureFlags(
            enableQuotes: true,
            enableCustomerManagement: true,
          ),
        ),
      ));

      expect(find.text('VENDER'), findsOneWidget);
      expect(find.text('INVENTARIO'), findsOneWidget);
      expect(find.text('CLIENTES'), findsOneWidget);
      expect(find.text('MI NEGOCIO'), findsOneWidget);
    });

    testWidgets('"Registrar venta" presente y destacado', (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'tienda_barrio',
          flags: FeatureFlags(),
        ),
      ));

      expect(find.text('Registrar venta'), findsOneWidget);
      // El módulo destacado tiene una Key dedicada.
      expect(find.byKey(const Key('dashboard_module_registrar_venta')),
          findsOneWidget);
      expect(find.byKey(const Key('dashboard_featured_registrar_venta')),
          findsOneWidget);
    });

    testWidgets('F037: "Análisis de Ganancias" presente como core',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'tienda_barrio',
          flags: FeatureFlags(),
        ),
      ));

      expect(find.text('Análisis de Ganancias'), findsOneWidget);
      expect(find.byKey(const Key('dashboard_module_analisis_ganancias')),
          findsOneWidget);
    });

    testWidgets('tienda_barrio sin flags NO ve módulos especializados',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'tienda_barrio',
          flags: FeatureFlags(),
        ),
      ));

      expect(find.text('Recetas y Platos'), findsNothing);
      expect(find.text('Trabajos de Muebles'), findsNothing);
      expect(find.text('Cotizaciones'), findsNothing);
      expect(find.text('Promociones'), findsNothing);
      expect(find.text('Mis Clientes'), findsNothing);
      // F037: Marketing Hub ya no es core, queda oculto sin la cap.
      expect(find.text('Marketing y Combos'), findsNothing);
      // Pero sí ve los módulos core.
      expect(find.text('Productos'), findsOneWidget);
      expect(find.text('Historial de ventas'), findsOneWidget);
      expect(find.text('Análisis de Ganancias'), findsOneWidget);
    });

    testWidgets('reparacion_muebles ve Trabajos de Muebles', (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'reparacion_muebles',
          flags: FeatureFlags(),
        ),
      ));

      expect(find.text('Trabajos de Muebles'), findsOneWidget);
    });

    testWidgets('una capacidad ON hace aparecer su módulo', (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'tienda_barrio',
          flags: FeatureFlags(enableCustomerManagement: true),
        ),
      ));

      expect(find.text('Mis Clientes'), findsOneWidget);
    });

    testWidgets('F037: activar enableMarketingHub hace aparecer el módulo',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'tienda_barrio',
          flags: FeatureFlags(enableMarketingHub: true),
        ),
      ));

      expect(find.text('Marketing y Combos'), findsOneWidget);
    });

    testWidgets('no hay overflow a 360dp', (tester) async {
      await tester.pumpWidget(_wrap(
        const DashboardModuleGrid(
          businessType: 'restaurante',
          flags: FeatureFlags(
            enableQuotes: true,
            enablePromotions: true,
            enableCustomerManagement: true,
            enableMarketingHub: true,
          ),
        ),
      ));
      // Si hubiera overflow, pumpWidget reportaría un error de render.
      expect(tester.takeException(), isNull);
    });
  });
}
