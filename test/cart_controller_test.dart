import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  late CartController ctrl;

  setUp(() {
    ctrl = CartController();
  });

  // ── Estado inicial ─────────────────────────────────────────────────────────

  group('Estado inicial', () {
    test('arranca en el carrito 0 (pestaña 1)', () {
      expect(ctrl.activeIndex, equals(0));
    });

    test('todos los 5 carritos empiezan vacíos', () {
      for (int i = 0; i < 5; i++) {
        expect(ctrl.cart(i), isEmpty, reason: 'carrito $i debe estar vacío');
      }
    });

    test('total del carrito activo vacío es 0', () {
      expect(ctrl.activeTotal, equals(0.0));
    });

    test('contiene exactamente 5 productos mock', () {
      expect(CartController.mockProducts.length, equals(5));
    });

    test('productos mock tienen precios > 0 y stock > 0', () {
      for (final p in CartController.mockProducts) {
        expect(p.price, greaterThan(0),
            reason: '${p.name} debe tener precio positivo');
        expect(p.stock, greaterThan(0),
            reason: '${p.name} debe tener stock positivo');
      }
    });
  });

  // ── Agregar productos ──────────────────────────────────────────────────────

  group('Agregar productos', () {
    test('agregar un producto crea CartItem con quantity=1', () {
      final p = CartController.mockProducts.first;
      ctrl.addProduct(p);

      expect(ctrl.activeCart.length, equals(1));
      expect(ctrl.activeCart.first.quantity, equals(1));
      expect(ctrl.activeCart.first.product.id, equals(p.id));
    });

    test('agregar el mismo producto dos veces incrementa quantity a 2', () {
      final p = CartController.mockProducts.first;
      ctrl.addProduct(p);
      ctrl.addProduct(p);

      expect(ctrl.activeCart.length, equals(1));
      expect(ctrl.activeCart.first.quantity, equals(2));
    });

    test('agregar 2 productos distintos crea 2 CartItems', () {
      ctrl.addProduct(CartController.mockProducts[0]);
      ctrl.addProduct(CartController.mockProducts[1]);

      expect(ctrl.activeCart.length, equals(2));
    });
  });

  // ── Incrementar / Decrementar ──────────────────────────────────────────────

  group('Incrementar cantidad', () {
    test('increment sube la cantidad de 1 a 2', () {
      final p = CartController.mockProducts.first;
      ctrl.addProduct(p);
      ctrl.increment(p);

      expect(ctrl.activeCart.first.quantity, equals(2));
    });

    test('increment en producto no existente no lanza excepción', () {
      final p = CartController.mockProducts.first;
      expect(() => ctrl.increment(p), returnsNormally);
    });
  });

  group('Decrementar cantidad', () {
    test('decrement de 2 → 1 reduce la cantidad', () {
      final p = CartController.mockProducts.first;
      ctrl.addProduct(p);
      ctrl.addProduct(p); // qty = 2
      ctrl.decrement(p);

      expect(ctrl.activeCart.first.quantity, equals(1));
    });

    test('decrement de 1 → 0 elimina el item del carrito', () {
      final p = CartController.mockProducts.first;
      ctrl.addProduct(p); // qty = 1
      ctrl.decrement(p);

      expect(ctrl.activeCart, isEmpty);
    });

    test('decrement en producto no existente no lanza excepción', () {
      final p = CartController.mockProducts.first;
      expect(() => ctrl.decrement(p), returnsNormally);
    });
  });

  // ── Cálculo del total ──────────────────────────────────────────────────────

  group('Cálculo del total', () {
    test('total = suma de (precio × cantidad) de todos los items', () {
      final p1 = CartController.mockProducts[0]; // precio conocido
      final p2 = CartController.mockProducts[1];

      ctrl.addProduct(p1); // qty=1
      ctrl.addProduct(p1); // qty=2
      ctrl.addProduct(p2); // qty=1

      final expected = (p1.price * 2) + (p2.price * 1);
      expect(ctrl.activeTotal, closeTo(expected, 0.01));
    });

    test('total formateado comienza con "\$"', () {
      ctrl.addProduct(CartController.mockProducts.first);
      expect(ctrl.formattedTotal, startsWith('\$'));
    });

    test('total es 0 al limpiar el carrito', () {
      ctrl.addProduct(CartController.mockProducts.first);
      ctrl.clearActiveCart();
      expect(ctrl.activeTotal, equals(0.0));
    });
  });

  // ── Carritos múltiples independientes ─────────────────────────────────────

  group('Carritos múltiples (pestañas)', () {
    test('agregar producto al carrito 0 no afecta al carrito 1', () {
      ctrl.addProduct(CartController.mockProducts.first); // carrito 0

      ctrl.switchCart(1);
      expect(ctrl.activeCart, isEmpty, reason: 'carrito 1 debe estar vacío');
    });

    test('cada carrito mantiene su propio estado de forma independiente', () {
      // Carrito 0: producto 0, qty=2
      ctrl.addProduct(CartController.mockProducts[0]);
      ctrl.addProduct(CartController.mockProducts[0]);

      // Carrito 1: producto 1, qty=1
      ctrl.switchCart(1);
      ctrl.addProduct(CartController.mockProducts[1]);

      // Verificar carrito 0
      ctrl.switchCart(0);
      expect(ctrl.activeCart.first.quantity, equals(2));
      expect(ctrl.activeCart.first.product.id,
          equals(CartController.mockProducts[0].id));

      // Verificar carrito 1
      ctrl.switchCart(1);
      expect(ctrl.activeCart.first.quantity, equals(1));
      expect(ctrl.activeCart.first.product.id,
          equals(CartController.mockProducts[1].id));
    });

    test('switchCart actualiza activeIndex', () {
      ctrl.switchCart(3);
      expect(ctrl.activeIndex, equals(3));
    });

    test('5 carritos simultáneos con contenidos distintos', () {
      for (int i = 0; i < 5; i++) {
        ctrl.switchCart(i);
        ctrl.addProduct(CartController.mockProducts[i]);
      }

      for (int i = 0; i < 5; i++) {
        ctrl.switchCart(i);
        expect(ctrl.activeCart.length, equals(1));
        expect(ctrl.activeCart.first.product.id,
            equals(CartController.mockProducts[i].id));
      }
    });

    test('clearActiveCart solo limpia el carrito activo', () {
      // Llenar los 5 carritos
      for (int i = 0; i < 5; i++) {
        ctrl.switchCart(i);
        ctrl.addProduct(CartController.mockProducts[i]);
      }

      // Limpiar solo el carrito 2
      ctrl.switchCart(2);
      ctrl.clearActiveCart();
      expect(ctrl.activeCart, isEmpty);

      // Los demás deben seguir con datos
      for (int i = 0; i < 5; i++) {
        if (i == 2) continue;
        ctrl.switchCart(i);
        expect(ctrl.activeCart, isNotEmpty,
            reason: 'carrito $i no debe haberse limpiado');
      }
    });

    test('cartCount devuelve la cantidad total de items del carrito', () {
      ctrl.addProduct(CartController.mockProducts[0]); // 1
      ctrl.addProduct(CartController.mockProducts[0]); // 2
      ctrl.addProduct(CartController.mockProducts[1]); // 1

      expect(ctrl.cartCount(0), equals(3)); // 2 + 1
    });

    test('cartCount de carrito vacío es 0', () {
      expect(ctrl.cartCount(4), equals(0));
    });
  });

  // ── Búsqueda ───────────────────────────────────────────────────────────────

  group('Filtrado de productos', () {
    test('sin búsqueda devuelve todos los mockProducts', () {
      expect(ctrl.filteredProducts.length,
          equals(CartController.mockProducts.length));
    });

    test('búsqueda filtra por nombre (case-insensitive)', () {
      final first = CartController.mockProducts.first;
      final partial = first.name.substring(0, 3).toLowerCase();

      ctrl.setSearch(partial);
      expect(ctrl.filteredProducts, contains(first));
    });

    test('búsqueda sin coincidencias devuelve lista vacía', () {
      ctrl.setSearch('zzzzzzz_no_existe');
      expect(ctrl.filteredProducts, isEmpty);
    });

    test('limpiar búsqueda restaura todos los productos', () {
      ctrl.setSearch('algo');
      ctrl.setSearch('');
      expect(ctrl.filteredProducts.length,
          equals(CartController.mockProducts.length));
    });
  });
}
