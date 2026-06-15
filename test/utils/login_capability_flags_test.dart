// Spec: specs/051-login-emite-capacidades/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/login_capability_flags.dart';

void main() {
  group('foldLoginCapabilityFlags', () {
    test('mergea las capacidades top-level dentro de feature_flags', () {
      // Shape REAL del login (Spec 051): feature_flags trae los 7 viejos,
      // las capacidades nuevas van en la RAÍZ.
      final data = {
        'feature_flags': {'enable_tables': true, 'enable_events': true},
        'enable_recipes': true,
        'enable_marketing_hub': true,
        'enable_quotes': true,
        'enable_customer_management': true,
        'enable_promotions': false,
        'enable_purchase_orders': false,
      };
      final merged = foldLoginCapabilityFlags(data);

      // viejos preservados
      expect(merged['enable_tables'], true);
      expect(merged['enable_events'], true);
      // nuevos activos mergeados (esto es lo que se perdía antes)
      expect(merged['enable_recipes'], true);
      expect(merged['enable_marketing_hub'], true);
      expect(merged['enable_quotes'], true);
      expect(merged['enable_customer_management'], true);
      // inactivos presentes en false (para poder apagar)
      expect(merged['enable_promotions'], false);
      expect(merged['enable_purchase_orders'], false);
    });

    test('sin feature_flags ni capacidades → mapa vacío (no lanza)', () {
      expect(foldLoginCapabilityFlags(const {}), isEmpty);
    });

    test('capacidad ausente NO se inventa (no la pone en false)', () {
      final merged = foldLoginCapabilityFlags({
        'feature_flags': {'enable_tables': true},
        'enable_recipes': true,
      });
      expect(merged.containsKey('enable_supplies'), isFalse);
      expect(merged['enable_recipes'], true);
    });
  });
}
