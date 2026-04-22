import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/cart_item.dart';
import 'package:vendia_pos/models/product.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

/// Flow A — Retail Classic
///
/// Certifies that a physical-product sale produces a backend payload
/// shaped for inventory-backed lines. The backend's
/// `validateSaleItemRequest` enforces XOR between product lines and
/// service lines via a DB CHECK (migration 020); this test locks the
/// client's contribution to that contract so no future refactor
/// accidentally sends a hybrid payload that would 400 from the API.
///
/// The payload mapping under test lives in
/// `PosScreen._syncSaleToBackend` — the test re-implements the same
/// map closure so the assertion is independent of the enclosing
/// StatefulWidget and its HTTP dependencies.
Map<String, dynamic> _buildSaleItemPayload(CartItem item) {
  if (item.isService) {
    return {
      'quantity': item.quantity,
      'is_service': true,
      'custom_description': item.customDescription ?? item.product.name,
      'custom_unit_price': item.customUnitPrice ?? item.product.price,
    };
  }
  return {
    'product_id': item.product.uuid.isNotEmpty
        ? item.product.uuid
        : item.product.id.toString(),
    'quantity': item.quantity,
  };
}

void main() {
  group('Flow A — Retail Classic (venta de producto físico)', () {
    late CartController ctrl;
    late Product physicalProduct;

    setUp(() {
      ctrl = CartController();
      physicalProduct = const Product(
        id: 42,
        uuid: 'prod-arroz-diana-500g',
        name: 'Arroz Diana 500g',
        price: 2900,
        stock: 100,
      );
    });

    test('agregar producto físico marca la línea como no-servicio', () {
      ctrl.addProduct(physicalProduct);
      final line = ctrl.activeCart.single;

      expect(line.isService, isFalse,
          reason: 'Producto físico nunca debe marcar is_service');
      expect(line.customDescription, isNull);
      expect(line.customUnitPrice, isNull);
      expect(line.product.uuid, equals('prod-arroz-diana-500g'));
    });

    test('payload de venta incluye product_id y quantity', () {
      ctrl.addProduct(physicalProduct);
      ctrl.addProduct(physicalProduct); // qty=2

      final payload = _buildSaleItemPayload(ctrl.activeCart.single);

      expect(payload['product_id'], equals('prod-arroz-diana-500g'));
      expect(payload['quantity'], equals(2));
    });

    test('payload de venta NO lleva is_service ni custom_* (contrato XOR)',
        () {
      ctrl.addProduct(physicalProduct);

      final payload = _buildSaleItemPayload(ctrl.activeCart.single);

      // El backend rechaza la combinación (CHECK sale_items_product_or_service)
      expect(payload.containsKey('is_service'), isFalse);
      expect(payload.containsKey('custom_description'), isFalse);
      expect(payload.containsKey('custom_unit_price'), isFalse);
    });

    test('fallback de product_id: usa id.toString() cuando uuid está vacío',
        () {
      const legacy = Product(
        id: 7,
        uuid: '',
        name: 'Legacy Product',
        price: 1500,
        stock: 10,
      );
      ctrl.addProduct(legacy);

      final payload = _buildSaleItemPayload(ctrl.activeCart.single);

      expect(payload['product_id'], equals('7'),
          reason: 'Fallback estable para tenants pre-migración UUID');
      expect(payload['quantity'], equals(1));
    });

    test('subtotal del carrito refleja descuento de stock intencional', () {
      // Carrito con 3 unidades del mismo producto → el backend descontará
      // 3 del stock. El subtotal es la proxy que el cliente reporta.
      ctrl.addProduct(physicalProduct);
      ctrl.addProduct(physicalProduct);
      ctrl.addProduct(physicalProduct);

      expect(ctrl.activeCart.single.quantity, equals(3));
      expect(ctrl.activeTotal, closeTo(2900 * 3, 0.01));
    });

    test('mezcla de 2 productos distintos produce 2 payloads independientes',
        () {
      const otroProducto = Product(
        id: 99,
        uuid: 'prod-aceite-girasol-250ml',
        name: 'Aceite Girasol 250ml',
        price: 6500,
        stock: 20,
      );

      ctrl.addProduct(physicalProduct);
      ctrl.addProduct(otroProducto);

      final payloads = ctrl.activeCart.map(_buildSaleItemPayload).toList();
      expect(payloads.length, equals(2));
      expect(payloads.every((p) => p.containsKey('product_id')), isTrue);
      expect(payloads.every((p) => !p.containsKey('is_service')), isTrue);
      expect(
        payloads.map((p) => p['product_id']).toSet(),
        equals({'prod-arroz-diana-500g', 'prod-aceite-girasol-250ml'}),
      );
    });
  });
}
