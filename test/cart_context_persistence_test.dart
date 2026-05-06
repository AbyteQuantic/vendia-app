import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Cart context persistence — switching tabs', () {
    test(
      'PO scenario: assign Mesa 4 to C0, assign Mesa 2 to C1, '
      'switch back to C0 — context still Mesa 4',
      () async {
        final c = CartController();
        c.switchCart(0);
        c.setContext(const AccountContext(
            type: AccountType.mesa, tableLabel: 'Mesa 4'));
        expect(c.activeContext.tableLabel, 'Mesa 4');

        c.switchCart(1);
        c.setContext(const AccountContext(
            type: AccountType.mesa, tableLabel: 'Mesa 2'));
        expect(c.activeContext.tableLabel, 'Mesa 2');

        c.switchCart(0);
        expect(c.activeContext.tableLabel, 'Mesa 4');
        expect(c.activeContext.type, AccountType.mesa);
      },
    );

    test(
      'switching to an empty cart returns mostrador (no leakage from '
      'other slots)',
      () async {
        final c = CartController();
        c.switchCart(0);
        c.setContext(const AccountContext(
            type: AccountType.mesa, tableLabel: 'Mesa 4'));
        c.switchCart(2);
        expect(c.activeContext.type, AccountType.mostrador);
        expect(c.activeContext.tableLabel, isNull);
      },
    );
  });

  group('Cleanup discriminant — hasBeenSynced gate', () {
    bool shouldCleanContext({
      required bool isMesa,
      required String label,
      required Set<String> openLabels,
      required String? sessionToken,
      required String? orderId,
    }) {
      final hasBeenSynced =
          (sessionToken != null && sessionToken.isNotEmpty) ||
              (orderId != null && orderId.isNotEmpty);
      return isMesa &&
          label.isNotEmpty &&
          !openLabels.contains(label) &&
          hasBeenSynced;
    }

    test(
      'fresh mesa (no sessionToken, no orderId) is preserved during polling',
      () {
        expect(
            shouldCleanContext(
              isMesa: true,
              label: 'Mesa 4',
              openLabels: const {},
              sessionToken: null,
              orderId: null,
            ),
            isFalse);
      },
    );

    test('synced mesa absent from server list IS cleaned (auto-close path)',
        () {
      expect(
          shouldCleanContext(
            isMesa: true,
            label: 'Mesa 4',
            openLabels: const {'Mesa 7'},
            sessionToken: 'srv-token-abc',
            orderId: 'ord-xyz',
          ),
          isTrue);
    });

    test('synced mesa STILL in server list is NOT cleaned', () {
      expect(
          shouldCleanContext(
            isMesa: true,
            label: 'Mesa 4',
            openLabels: const {'Mesa 4', 'Mesa 7'},
            sessionToken: 'srv-token-abc',
            orderId: 'ord-xyz',
          ),
          isFalse);
    });

    test(
      'mesa with only orderId (no sessionToken) — synced enough to clean',
      () {
        expect(
            shouldCleanContext(
              isMesa: true,
              label: 'Mesa 4',
              openLabels: const {},
              sessionToken: null,
              orderId: 'ord-xyz',
            ),
            isTrue);
      },
    );

    test('non-mesa contexts are never touched by this cleanup', () {
      expect(
          shouldCleanContext(
            isMesa: false,
            label: 'Some Label',
            openLabels: const {},
            sessionToken: 'token',
            orderId: 'ord',
          ),
          isFalse);
    });
  });
}
