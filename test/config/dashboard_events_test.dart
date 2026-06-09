// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/dashboard_modules.dart';
import 'package:vendia_pos/config/screen_registry.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/utils/business_capability_map.dart';

void main() {
  group('Dashboard — módulo Eventos (F042)', () {
    test('oculto cuando enable_events está OFF', () {
      const flags = FeatureFlags();
      final visible = visibleModulesFor('tienda_barrio', flags);
      expect(visible.any((m) => m.id == 'eventos'), isFalse);
    });

    test('visible cuando enable_events está ON', () {
      const flags = FeatureFlags(enableEvents: true);
      final visible = visibleModulesFor('tienda_barrio', flags);
      expect(visible.any((m) => m.id == 'eventos'), isTrue);
    });

    test('aparece en el reel de capacidades cuando está OFF', () {
      const flags = FeatureFlags();
      final reel = unactivatedOptionalModules(flags);
      expect(reel.any((m) => m.id == 'eventos'), isTrue);
    });

    test('capabilityEnabled mapea events → enableEvents', () {
      expect(
        capabilityEnabled(
            OptionalCapability.events, const FeatureFlags(enableEvents: true)),
        isTrue,
      );
      expect(
        capabilityEnabled(OptionalCapability.events, const FeatureFlags()),
        isFalse,
      );
    });

    test('FeatureFlags.fromJson lee enable_events', () {
      expect(FeatureFlags.fromJson({'enable_events': true}).enableEvents, isTrue);
      expect(FeatureFlags.fromJson({}).enableEvents, isFalse);
    });

    test('ScreenRegistry resuelve la pantalla nativa "eventos"', () {
      expect(hasNativeScreen('eventos'), isTrue);
    });
  });
}
