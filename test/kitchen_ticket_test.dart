// Spec: specs/105-hito-restaurante-comandas/spec.md — F2 (mostrador prepago).
//
// El POS, tras cobrar en mostrador/mesa inmediata, arma la comanda PREPAGO
// (sale_uuid → paid_at server-side) SOLO cuando el pedido trae platos de
// menú. Una tienda vendiendo mecato jamás molesta a la cocina.
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/cart_item.dart';
import 'package:vendia_pos/models/product.dart';
import 'package:vendia_pos/screens/pos/kitchen_ticket.dart';

Product _p({
  required String uuid,
  required String name,
  double price = 10000,
  bool isMenuItem = false,
}) =>
    Product(
      id: 0,
      uuid: uuid,
      name: name,
      price: price,
      stock: 10,
      isMenuItem: isMenuItem,
    );

void main() {
  group('buildKitchenTicketPayload (Spec 105 F2)', () {
    test('sin platos de menú → null (no molesta a la cocina)', () {
      final items = [
        CartItem(product: _p(uuid: 'a', name: 'Gaseosa')),
        CartItem(product: _p(uuid: 'b', name: 'Papas'), quantity: 2),
      ];
      expect(
        buildKitchenTicketPayload(items,
            saleUuid: 's1', label: 'Pedido 3'),
        isNull,
      );
    });

    test('con plato → payload prepago completo (incluye acompañamientos)',
        () {
      final items = [
        CartItem(
            product: _p(uuid: 'a', name: 'Bandeja', isMenuItem: true),
            quantity: 1),
        CartItem(product: _p(uuid: 'b', name: 'Gaseosa', price: 3000),
            quantity: 2),
      ];
      final payload = buildKitchenTicketPayload(items,
          saleUuid: 'sale-9', label: 'Pedido 7', customerName: 'Juan');

      expect(payload, isNotNull);
      expect(payload!['sale_uuid'], 'sale-9');
      expect(payload['label'], 'Pedido 7');
      expect(payload['type'], 'turno');
      expect(payload['customer_name'], 'Juan');
      final lines = payload['items'] as List;
      // El chef arma el pedido COMPLETO: plato + gaseosa.
      expect(lines, hasLength(2));
      expect(
          lines.first,
          containsPair('product_uuid', 'a'));
      expect(lines.first, containsPair('quantity', 1));
      expect((lines.first as Map)['unit_price'], greaterThan(0));
    });

    test('excluye líneas de servicio ad-hoc y precios inválidos', () {
      final items = [
        CartItem(
            product: _p(uuid: 'a', name: 'Empanada', isMenuItem: true),
            quantity: 4),
        CartItem(
          product: _p(uuid: '', name: 'Domicilio', price: 0),
          isService: true,
          customDescription: 'Domicilio',
          customUnitPrice: 5000,
        ),
        CartItem(product: _p(uuid: 'c', name: 'Regalo', price: 0)),
      ];
      final payload = buildKitchenTicketPayload(items,
          saleUuid: 's2', label: 'Mesa 4', type: 'mesa');

      expect(payload, isNotNull);
      expect(payload!['type'], 'mesa');
      final lines = payload['items'] as List;
      expect(lines, hasLength(1));
      expect(lines.first, containsPair('product_name', 'Empanada'));
    });

    test('customer_name vacío no viaja', () {
      final items = [
        CartItem(
            product: _p(uuid: 'a', name: 'Perro', isMenuItem: true)),
      ];
      final payload = buildKitchenTicketPayload(items,
          saleUuid: 's3', label: 'Pedido 1', customerName: '  ');
      expect(payload!.containsKey('customer_name'), isFalse);
    });
  });
}
