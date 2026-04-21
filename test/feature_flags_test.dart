import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

/// Parse + default-fallback behavior mirrors the backend contract in
/// handlers/workspace.go — missing keys default to false so a legacy
/// tenant (pre-migration-021 login) never sees modules turned on by
/// accident.
void main() {
  group('FeatureFlags.fromJson', () {
    test('parses all six flags when present', () {
      final flags = FeatureFlags.fromJson(const {
        'enable_tables': true,
        'enable_kds': true,
        'enable_tips': true,
        'enable_services': true,
        'enable_custom_billing': true,
        'enable_fractional_units': true,
      });
      expect(flags.enableTables, isTrue);
      expect(flags.enableKDS, isTrue);
      expect(flags.enableTips, isTrue);
      expect(flags.enableServices, isTrue);
      expect(flags.enableCustomBilling, isTrue);
      expect(flags.enableFractionalUnits, isTrue);
    });

    test('missing keys default to false', () {
      final flags = FeatureFlags.fromJson(const {});
      expect(flags.enableTables, isFalse);
      expect(flags.enableServices, isFalse);
    });

    test('non-bool values coerce to false', () {
      final flags = FeatureFlags.fromJson(const {
        'enable_services': 'yes',
        'enable_tables': 1,
      });
      expect(flags.enableServices, isFalse);
      expect(flags.enableTables, isFalse);
    });

    test('default constructor produces all-false', () {
      const flags = FeatureFlags();
      expect(flags.enableTables, isFalse);
      expect(flags.enableKDS, isFalse);
      expect(flags.enableTips, isFalse);
      expect(flags.enableServices, isFalse);
      expect(flags.enableCustomBilling, isFalse);
      expect(flags.enableFractionalUnits, isFalse);
    });
  });

  group('CartController.addServiceCharge', () {
    late CartController ctrl;
    setUp(() => ctrl = CartController());

    test('adds an is_service line with custom description + price', () {
      ctrl.addServiceCharge(description: 'Reparación mesa', unitPrice: 50000);
      expect(ctrl.activeCart, hasLength(1));
      final line = ctrl.activeCart.first;
      expect(line.isService, isTrue);
      expect(line.customDescription, 'Reparación mesa');
      expect(line.customUnitPrice, 50000);
      expect(line.product.name, 'Reparación mesa');
    });

    test('subtotal respects quantity', () {
      ctrl.addServiceCharge(
          description: 'Corte', unitPrice: 20000, quantity: 3);
      expect(ctrl.activeCart.single.subtotal, 60000);
    });

    test('ignores empty description', () {
      ctrl.addServiceCharge(description: '   ', unitPrice: 10000);
      expect(ctrl.activeCart, isEmpty);
    });

    test('ignores non-positive price', () {
      ctrl.addServiceCharge(description: 'X', unitPrice: 0);
      expect(ctrl.activeCart, isEmpty);
    });

    test('serialises is_service fields in toJson', () {
      ctrl.addServiceCharge(description: 'Instalación', unitPrice: 30000);
      final json = ctrl.activeCart.single.toJson();
      expect(json['is_service'], isTrue);
      expect(json['custom_description'], 'Instalación');
      expect(json['custom_unit_price'], 30000);
    });

    test('each call produces a distinct line even on matching description',
        () {
      ctrl.addServiceCharge(description: 'Visita técnica', unitPrice: 10000);
      ctrl.addServiceCharge(description: 'Visita técnica', unitPrice: 10000);
      expect(ctrl.activeCart, hasLength(2));
    });
  });
}
