// Spec: specs/105-hito-restaurante-comandas/spec.md — F3 (roles → módulos).
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/config/catalog_merge.dart';
import 'package:vendia_pos/services/auth_service.dart' show FeatureFlags;

void main() {
  group('moduleWhitelistForRole (Spec 105 F3)', () {
    test('chef ve SOLO comandas (nada de dinero)', () {
      final w = moduleWhitelistForRole('chef', const FeatureFlags());
      expect(w, ['comandas']);
    });

    test('mesero puro: mesas y comandas, SIN registrar venta', () {
      final w = moduleWhitelistForRole('waiter', const FeatureFlags());
      expect(w, containsAll(['comandas', 'mesas']));
      expect(w, isNot(contains('registrar_venta')));
    });

    test('mesero con toggle del dueño: gana Registrar Venta', () {
      final w = moduleWhitelistForRole(
          'waiter', const FeatureFlags(enableWaiterCharge: true));
      expect(w, contains('registrar_venta'));
    });

    test('courier = etiqueta con preset de mesero (sin vista propia v1)', () {
      final w = moduleWhitelistForRole('courier', const FeatureFlags());
      expect(w, containsAll(['comandas', 'mesas']));
    });

    test('owner/admin/cashier/legacy: SIN filtro (retro-compat del concilio)',
        () {
      for (final role in ['owner', 'admin', 'cashier', '']) {
        expect(moduleWhitelistForRole(role, const FeatureFlags()), isNull,
            reason: 'rol $role conserva el dashboard completo');
      }
    });
  });
}
