import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/models/product.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CartController — cross-deletion regression', () {
    test(
      'decrement on B does NOT remove A when both share id=0 (production scenario for items without serverId)',
      () async {
        final c = CartController();
        const a = Product(
            id: 0, uuid: 'uuid-agua', name: 'Agua', price: 1000, stock: 50);
        const b = Product(
            id: 0, uuid: 'uuid-bretana', name: 'Bretaña', price: 2000, stock: 50);

        c.addProduct(a);
        c.addProduct(b);
        expect(c.activeCart.length, 2);

        // The cashier taps delete (decrement at qty=1) on B.
        c.decrement(b);

        // Bug regression: A must still be present, only B removed.
        expect(c.activeCart.length, 1);
        expect(c.activeCart.first.product.uuid, 'uuid-agua');
      },
    );

    test('increment on B updates B not A when ids collide', () async {
      final c = CartController();
      const a = Product(
          id: 0, uuid: 'uuid-agua', name: 'Agua', price: 1000, stock: 50);
      const b = Product(
          id: 0, uuid: 'uuid-bretana', name: 'Bretaña', price: 2000, stock: 50);

      c.addProduct(a);
      c.addProduct(b);

      c.increment(b);

      final aLine = c.activeCart.firstWhere((i) => i.product.uuid == 'uuid-agua');
      final bLine = c.activeCart.firstWhere((i) => i.product.uuid == 'uuid-bretana');
      expect(aLine.quantity, 1);
      expect(bLine.quantity, 2);
    });
  });
}
