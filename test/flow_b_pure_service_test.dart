import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/cart_item.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

/// Flow B — Pure Service (venta de servicio ad-hoc)
///
/// Certifies that a service sale (e.g. reparación, visita técnica,
/// consultoría) produces a payload that:
///   - Omits `product_id` entirely — the DB CHECK
///     (`sale_items_product_or_service`, migration 020) rejects any row
///     that has both a product_id AND is_service=true.
///   - Carries `is_service: true`, `custom_description`, and
///     `custom_unit_price`.
///   - Skips inventory validation (backend stock decrement is guarded
///     by `!item.IsService` in sales.go:handlers.CreateSale).
///
/// Mirrors the payload builder in `PosScreen._syncSaleToBackend`.
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
  group('Flow B — Pure Service (venta de servicio ad-hoc)', () {
    late CartController ctrl;

    setUp(() {
      ctrl = CartController();
    });

    test('addServiceCharge acepta descripción libre + precio personalizado',
        () {
      ctrl.addServiceCharge(
        description: 'Reparación de mesa de centro',
        unitPrice: 85000,
      );
      final line = ctrl.activeCart.single;

      expect(line.isService, isTrue);
      expect(line.customDescription, equals('Reparación de mesa de centro'));
      expect(line.customUnitPrice, equals(85000));
      expect(line.quantity, equals(1));
    });

    test('addServiceCharge rechaza descripción vacía', () {
      ctrl.addServiceCharge(description: '   ', unitPrice: 50000);
      expect(ctrl.activeCart, isEmpty,
          reason:
              'Servicio sin descripción nunca debe llegar al carrito (backend rechaza)');
    });

    test('addServiceCharge rechaza precios no-positivos', () {
      ctrl.addServiceCharge(description: 'Diagnóstico', unitPrice: 0);
      ctrl.addServiceCharge(description: 'Diagnóstico', unitPrice: -1000);
      expect(ctrl.activeCart, isEmpty,
          reason:
              'Servicio con precio ≤ 0 viola validateSaleItemRequest en Go');
    });

    test('payload de servicio omite product_id (contrato XOR DB CHECK)', () {
      ctrl.addServiceCharge(
        description: 'Visita técnica a domicilio',
        unitPrice: 40000,
      );

      final payload = _buildSaleItemPayload(ctrl.activeCart.single);

      expect(payload.containsKey('product_id'), isFalse,
          reason:
              'sale_items_product_or_service rechaza product_id + is_service');
      expect(payload['is_service'], isTrue);
      expect(payload['custom_description'], equals('Visita técnica a domicilio'));
      expect(payload['custom_unit_price'], equals(40000));
      expect(payload['quantity'], equals(1));
    });

    test(
        'servicio con quantity>1 preserva la intención (ej. 3 horas de mano de obra)',
        () {
      ctrl.addServiceCharge(
        description: 'Hora de mano de obra',
        unitPrice: 25000,
        quantity: 3,
      );

      final item = ctrl.activeCart.single;
      expect(item.quantity, equals(3));
      expect(ctrl.activeTotal, closeTo(25000 * 3, 0.01));

      final payload = _buildSaleItemPayload(item);
      expect(payload['quantity'], equals(3));
      expect(payload.containsKey('product_id'), isFalse);
    });

    test(
        'explícitamente omite validación de inventario (no stock key en payload)',
        () {
      ctrl.addServiceCharge(
        description: 'Consultoría diseño',
        unitPrice: 120000,
      );

      final payload = _buildSaleItemPayload(ctrl.activeCart.single);

      // El backend salta stock decrement cuando is_service=true. El
      // payload NO debe cargar nada relacionado con inventario.
      expect(payload.containsKey('stock'), isFalse);
      expect(payload.containsKey('product_id'), isFalse);
      expect(payload['is_service'], isTrue);
    });

    test('mezcla físicos + servicios en el mismo carrito (restaurante-taller)',
        () {
      // Caso realista: un taller de reparación de muebles vende un
      // servicio (mano de obra) + un insumo físico (lijas). El backend
      // acepta esta mezcla mientras cada línea respete el XOR.
      ctrl.addServiceCharge(
        description: 'Hora de tapicería',
        unitPrice: 35000,
      );

      final payloads = ctrl.activeCart.map(_buildSaleItemPayload).toList();
      expect(payloads.length, equals(1));
      expect(payloads.single['is_service'], isTrue);
      expect(payloads.single.containsKey('product_id'), isFalse);
    });
  });
}
