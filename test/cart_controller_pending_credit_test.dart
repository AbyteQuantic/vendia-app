import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

/// P0 hot-fix: pending-fiado slot lock.
///
/// The cashier kicks off a fiado handshake from the checkout screen and
/// hits "Seguir vendiendo" while the customer hasn't accepted yet. The
/// cart slot must STAY ALIVE until either:
///   1. the polling sweep sees the credit move off `status=pending`, or
///   2. the cashier explicitly cancels the handshake.
///
/// These tests pin the three invariants that broke in production:
///   • the cart of a pending fiado survives a `switchCart`,
///   • `clearActiveCart` is a no-op while the slot is locked,
///   • when the server confirms acceptance, the slot releases on its own.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AccountContext.pendingCreditAccountId', () {
    test('default value is null (defensive — old serialised payloads work)',
        () {
      const ctx = AccountContext();
      expect(ctx.pendingCreditAccountId, isNull);
      expect(ctx.hasPendingCredit, isFalse);
    });

    test('hasPendingCredit is true when id is present', () {
      const ctx = AccountContext(pendingCreditAccountId: 'credit-abc');
      expect(ctx.hasPendingCredit, isTrue);
    });

    test('copyWith preserves pendingCreditAccountId across other field edits',
        () {
      const ctx = AccountContext(
        type: AccountType.mostrador,
        pendingCreditAccountId: 'credit-xyz',
      );
      final next = ctx.copyWith(customerName: 'Don Carlos');
      expect(next.pendingCreditAccountId, 'credit-xyz');
      expect(next.customerName, 'Don Carlos');
    });

    test('clearPendingCredit drops the lock but keeps customer info', () {
      const ctx = AccountContext(
        customerName: 'Marta',
        customerPhone: '3001234567',
        pendingCreditAccountId: 'credit-1',
      );
      final cleared = ctx.clearPendingCredit();
      expect(cleared.pendingCreditAccountId, isNull);
      expect(cleared.hasPendingCredit, isFalse);
      expect(cleared.customerName, 'Marta',
          reason: 'customer info kept so the cashier can re-fiar without '
              'retyping');
    });

    test('toJson + fromJson round-trip preserves pendingCreditAccountId', () {
      const ctx = AccountContext(
        type: AccountType.mostrador,
        customerName: 'Don Carlos',
        pendingCreditAccountId: 'credit-rt-1',
      );
      final json = ctx.toJson();
      final back = AccountContext.fromJson(json);
      expect(back.pendingCreditAccountId, 'credit-rt-1');
      expect(back.customerName, 'Don Carlos');
    });

    test('fromJson without pendingCreditAccountId key defaults to null', () {
      // Old persisted payloads from pre-fiado-lock builds don't carry
      // the field. Make sure the parse stays graceful.
      final back = AccountContext.fromJson({
        'type': 'mostrador',
        'customerName': 'Old Build',
      });
      expect(back.pendingCreditAccountId, isNull);
      expect(back.customerName, 'Old Build');
    });
  });

  group('CartController — invariant 1: cart survives switchCart', () {
    test(
      'setPendingCredit on C0, switch to C1 and back to C0 — cart and '
      'pending lock survive intact',
      () async {
        final c = CartController();
        c.switchCart(0);
        c.addProduct(CartController.mockProducts[0]);
        c.addProduct(CartController.mockProducts[1]);
        final beforeCount = c.activeCart.length;

        c.setPendingCreditOnActive(
          creditAccountId: 'credit-survive-1',
          customerName: 'Don Carlos',
          customerPhone: '3001112233',
        );
        expect(c.activeContext.hasPendingCredit, isTrue);
        expect(c.activeContext.pendingCreditAccountId, 'credit-survive-1');

        c.switchCart(1);
        expect(c.activeIndex, 1);
        expect(c.activeContext.hasPendingCredit, isFalse,
            reason: 'C1 must not inherit the lock');

        c.switchCart(0);
        expect(c.activeContext.pendingCreditAccountId, 'credit-survive-1',
            reason: 'lock survived the switch');
        expect(c.activeContext.customerName, 'Don Carlos');
        expect(c.activeCart.length, beforeCount,
            reason: 'cart items survived the switch');
      },
    );

    test('cart of a locked slot survives switchCart and addProduct on it',
        () async {
      final c = CartController();
      c.switchCart(2);
      c.addProduct(CartController.mockProducts[0]);
      c.setPendingCreditOnActive(
        creditAccountId: 'credit-2',
        customerName: 'Marta',
      );
      // Cliente pide otra cosa antes de aceptar — la spec lo permite.
      c.addProduct(CartController.mockProducts[1]);
      expect(c.activeCart.length, 2);

      c.switchCart(0);
      c.switchCart(2);
      expect(c.activeCart.length, 2,
          reason: 'extra item added before customer accept must persist');
      expect(c.activeContext.pendingCreditAccountId, 'credit-2');
    });
  });

  group('CartController — invariant 2: clearActiveCart guarded', () {
    test(
      'clearActiveCart is a no-op while pendingCreditAccountId is set',
      () async {
        final c = CartController();
        c.addProduct(CartController.mockProducts[0]);
        c.setPendingCreditOnActive(
          creditAccountId: 'credit-guard-1',
          customerName: 'Marta',
        );

        final cleared = c.clearActiveCart();

        expect(cleared, isFalse,
            reason: 'method must report it refused to clear');
        expect(c.activeCart, isNotEmpty,
            reason: 'cart preserved on locked slot');
        expect(c.activeContext.pendingCreditAccountId, 'credit-guard-1',
            reason: 'context preserved on locked slot');
      },
    );

    test(
      'clearActiveCart with force:true clears even when locked',
      () async {
        final c = CartController();
        c.addProduct(CartController.mockProducts[0]);
        c.setPendingCreditOnActive(
          creditAccountId: 'credit-force-1',
          customerName: 'Don Pedro',
        );

        final cleared = c.clearActiveCart(force: true);

        expect(cleared, isTrue);
        expect(c.activeCart, isEmpty);
        expect(c.activeContext.hasPendingCredit, isFalse);
        expect(c.activeContext.type, AccountType.mostrador);
      },
    );

    test('clearActiveCart on an unlocked slot keeps original semantics',
        () async {
      final c = CartController();
      c.addProduct(CartController.mockProducts[0]);
      final cleared = c.clearActiveCart();
      expect(cleared, isTrue);
      expect(c.activeCart, isEmpty);
    });

    test('clearCartKeepContext is also guarded against pending fiado',
        () async {
      final c = CartController();
      c.addProduct(CartController.mockProducts[0]);
      c.setPendingCreditOnActive(
        creditAccountId: 'credit-keep-1',
      );

      final cleared = c.clearCartKeepContext();

      expect(cleared, isFalse);
      expect(c.activeCart, isNotEmpty);
      expect(c.activeContext.pendingCreditAccountId, 'credit-keep-1');
    });

    test(
      'cancelPendingCreditOnActive returns the credit_id and clears '
      'cart + context (this is the explicit cashier cancel path)',
      () async {
        final c = CartController();
        c.addProduct(CartController.mockProducts[0]);
        c.setPendingCreditOnActive(creditAccountId: 'credit-cancel-1');

        final id = c.cancelPendingCreditOnActive();

        expect(id, 'credit-cancel-1');
        expect(c.activeCart, isEmpty);
        expect(c.activeContext.hasPendingCredit, isFalse);
        expect(c.activeContext.type, AccountType.mostrador);
      },
    );

    test(
      'cancelPendingCreditOnActive returns null when nothing is locked',
      () async {
        final c = CartController();
        expect(c.cancelPendingCreditOnActive(), isNull);
      },
    );
  });

  group('CartController — invariant 3: server-driven release', () {
    test(
      'releasePendingCredits clears every slot whose pending id is in '
      'the accepted/rejected set',
      () async {
        final c = CartController();
        // Slot 0 → credit-A, slot 3 → credit-B, slot 7 → credit-C
        c.switchCart(0);
        c.addProduct(CartController.mockProducts[0]);
        c.setPendingCreditOnActive(
            creditAccountId: 'credit-A', customerName: 'A');

        c.switchCart(3);
        c.addProduct(CartController.mockProducts[1]);
        c.setPendingCreditOnActive(
            creditAccountId: 'credit-B', customerName: 'B');

        c.switchCart(7);
        c.addProduct(CartController.mockProducts[2]);
        c.setPendingCreditOnActive(
            creditAccountId: 'credit-C', customerName: 'C');

        // Server says A and C are no longer pending → release them.
        // B is still pending → must stay.
        final released =
            c.releasePendingCredits(const ['credit-A', 'credit-C']);

        expect(released, containsAll(<int>[0, 7]));
        expect(released.contains(3), isFalse);
        expect(c.contextAt(0).hasPendingCredit, isFalse);
        expect(c.cart(0), isEmpty);
        expect(c.contextAt(7).hasPendingCredit, isFalse);
        expect(c.cart(7), isEmpty);
        // B still locked.
        expect(c.contextAt(3).pendingCreditAccountId, 'credit-B');
        expect(c.cart(3), isNotEmpty);
      },
    );

    test('pendingCreditAccountIds reflects every locked slot', () async {
      final c = CartController();
      c.switchCart(0);
      c.setPendingCreditOnActive(creditAccountId: 'X');
      c.switchCart(2);
      c.setPendingCreditOnActive(creditAccountId: 'Y');

      expect(c.pendingCreditAccountIds, equals({'X', 'Y'}));
    });

    test('slotForPendingCredit finds the right slot index', () async {
      final c = CartController();
      c.switchCart(5);
      c.setPendingCreditOnActive(creditAccountId: 'find-me');
      expect(c.slotForPendingCredit('find-me'), 5);
      expect(c.slotForPendingCredit('not-there'), -1);
      expect(c.slotForPendingCredit(''), -1);
    });

    test('releasePendingCredits is a no-op for an empty input', () async {
      final c = CartController();
      c.setPendingCreditOnActive(creditAccountId: 'X');
      final released = c.releasePendingCredits(const <String>[]);
      expect(released, isEmpty);
      expect(c.activeContext.pendingCreditAccountId, 'X');
    });
  });

  group('Persistence', () {
    test(
      'pendingCreditAccountId survives a process restart via SharedPreferences',
      () async {
        final c1 = CartController();
        c1.switchCart(0);
        c1.addProduct(CartController.mockProducts[0]);
        c1.setPendingCreditOnActive(
          creditAccountId: 'credit-persist-1',
          customerName: 'Bryan',
        );
        // Give the persistence Future a tick to flush.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Simulate process restart — fresh CartController reads from
        // the same in-memory mock SharedPreferences.
        final c2 = CartController();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(c2.contextAt(0).pendingCreditAccountId, 'credit-persist-1',
            reason: 'lock survives restart');
        expect(c2.contextAt(0).customerName, 'Bryan');
      },
    );
  });
}
