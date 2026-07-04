// Spec: specs/095-variantes-producto/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/auth_service.dart';

void main() {
  group('FeatureFlags.enableProductVariants', () {
    test('true cuando el login lo trae en true', () {
      final flags = FeatureFlags.fromJson({'enable_product_variants': true});
      expect(flags.enableProductVariants, isTrue);
    });

    test('default false cuando el tenant no lo trae (legacy/pre-migración)', () {
      final flags = FeatureFlags.fromJson(const {});
      expect(flags.enableProductVariants, isFalse);
    });

    test('false explícito se respeta (para poder apagarla)', () {
      final flags = FeatureFlags.fromJson({'enable_product_variants': false});
      expect(flags.enableProductVariants, isFalse);
    });
  });
}
