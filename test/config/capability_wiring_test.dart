// Spec: auditoría de capacidades (reel→activador→carrusel→módulo).
//
// Verifica el CABLEADO estructural de las capacidades opcionales: que cada una
// que debe aparecer en el carrusel tenga su DashboardModule, y que el registry
// tenga la metadata necesaria para activar + mostrar foto + poder quitarse.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/dashboard_modules.dart';
import 'package:vendia_pos/screens/capabilities/capabilities_registry.dart';
import 'package:vendia_pos/utils/business_capability_map.dart';

void main() {
  DashboardModule? moduleFor(OptionalCapability cap) {
    for (final m in dashboardModules) {
      if (m.capability == cap) return m;
    }
    return null;
  }

  group('DashboardModule por capacidad (sube al carrusel cuando activa)', () {
    // Mesas: faltaba su módulo → enable_tables persistía pero nunca aparecía.
    test('tables tiene DashboardModule', () {
      expect(moduleFor(OptionalCapability.tables), isNotNull);
    });
    test('events tiene DashboardModule (referencia)', () {
      expect(moduleFor(OptionalCapability.events), isNotNull);
    });
    test('recipes/quotes/customers/promotions/marketing/purchaseOrders tienen módulo',
        () {
      for (final cap in [
        OptionalCapability.recipes,
        OptionalCapability.quotes,
        OptionalCapability.customerManagement,
        OptionalCapability.promotions,
        OptionalCapability.marketingHub,
        OptionalCapability.purchaseOrders,
      ]) {
        expect(moduleFor(cap), isNotNull, reason: '$cap sin DashboardModule');
      }
    });

    // Capacidades de comportamiento: antes NO tenían módulo → al activarlas no
    // aparecían en el carrusel. Ahora apuntan a su CapabilityScaffold.
    test('priceTiers/services/fractionalUnits tienen módulo (carrusel)', () {
      for (final cap in [
        OptionalCapability.priceTiers,
        OptionalCapability.services,
        OptionalCapability.fractionalUnits,
      ]) {
        final m = moduleFor(cap);
        expect(m, isNotNull, reason: '$cap sin DashboardModule');
        // El destino abre algo (su scaffold) — no es null.
        expect(m!.destination, isNotNull);
      }
    });
  });

  group('capabilitiesRegistry — metadata para activar + carrusel', () {
    // Cotizaciones DEBE estar en el registry para tener foto hero + onRemove
    // (antes era la única capacidad activa no removible).
    test('quotes está en el registry con configKey enable_quotes', () {
      final meta = capabilitiesRegistry[OptionalCapability.quotes];
      expect(meta, isNotNull);
      expect(meta!.configKey, 'enable_quotes');
      expect(meta.heroPhotoUrl, isNotEmpty);
      expect(meta.primaryDestination, isNotNull);
    });

    // Clientes va por el scaffold (activa el flag), así que necesita metadata.
    test('customerManagement está en el registry y activa el flag', () {
      final meta = capabilitiesRegistry[OptionalCapability.customerManagement];
      expect(meta, isNotNull);
      expect(meta!.profileKey, 'enable_customer_management');
      expect(meta.primaryDestination, isNotNull);
    });

    // Toda capacidad del registry con primaryDestination debe poder quitarse:
    // _buildActiveCapabilityCards usa configKey para desactivar.
    test('cada metadata con primaryDestination trae configKey (removible)', () {
      capabilitiesRegistry.forEach((cap, meta) {
        if (meta.primaryDestination != null) {
          expect(meta.configKey, isNotEmpty,
              reason: '$cap con módulo pero sin configKey → no removible');
        }
      });
    });
  });
}
