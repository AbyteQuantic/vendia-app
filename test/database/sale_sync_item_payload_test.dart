// Regresión: una venta offline con línea de SERVICIO debe sincronizar bien.
// Antes pushToServer mandaba el servicio como producto (product_id sintético)
// → el backend abortaba la venta entera y nunca sincronizaba (pérdida).
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/local_sale.dart';
import 'package:vendia_pos/database/sync/sales_sync.dart';

SaleItemEmbed item(String uuid, String name, int qty, double price) =>
    SaleItemEmbed()
      ..productUuid = uuid
      ..productName = name
      ..quantity = qty
      ..unitPrice = price
      ..isContainerCharge = false;

void main() {
  group('saleSyncItemPayload', () {
    test('servicio (service_…) → is_service + custom_unit_price (NO product_id)',
        () {
      final p = saleSyncItemPayload(
          item('service_123456', 'Domicilio', 1, 3000));
      expect(p['is_service'], true);
      expect(p['custom_description'], 'Domicilio');
      expect(p['custom_unit_price'], 3000);
      expect(p.containsKey('product_id'), isFalse);
    });

    test('producto normal → product_id + unit_price (precio efectivo)', () {
      final p = saleSyncItemPayload(
          item('a1b2c3d4-0000-4000-8000-000000000000', 'Arroz', 2, 4200));
      expect(p['product_id'], 'a1b2c3d4-0000-4000-8000-000000000000');
      expect(p['quantity'], 2);
      expect(p['unit_price'], 4200);
      expect(p.containsKey('is_service'), isFalse);
    });
  });
}
