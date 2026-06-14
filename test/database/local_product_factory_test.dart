// Spec: specs/047-offline-sync-contract/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/local_product_factory.dart';

void main() {
  group('buildSavedLocalProduct — no cae en la trampa del late reservedStock', () {
    test('toJson() NO lanza (antes: LateInitializationError por reservedStock)',
        () {
      final p = buildSavedLocalProduct(
        uuid: 'p-1',
        name: 'ProductoOffline',
        price: 5000,
        stock: 1,
        clientUpdatedAt: DateTime(2026),
      );
      // toJson() lee reservedStock; si no estuviera seteado, esto explotaría.
      // Es el mismo acceso que hace Isar al serializar en put().
      expect(() => p.toJson(), returnsNormally);
      expect(p.toJson()['reserved_stock'], 0);
    });

    test('reservedStock arranca en 0 y availableStock = stock', () {
      final p = buildSavedLocalProduct(
        uuid: 'p-2', name: 'X', price: 1000, stock: 10,
        clientUpdatedAt: DateTime(2026),
      );
      expect(p.reservedStock, 0);
      expect(p.availableStock, 10); // 10 - 0
    });

    test('mapea todos los campos del formulario', () {
      final p = buildSavedLocalProduct(
        uuid: 'p-3',
        name: 'Arroz',
        price: 4200,
        stock: 24,
        imageUrl: 'https://r2/arroz.png',
        barcode: '7702',
        presentation: 'bolsa',
        content: '500g',
        clientUpdatedAt: DateTime(2026),
      );
      expect(p.uuid, 'p-3');
      expect(p.name, 'Arroz');
      expect(p.price, 4200);
      expect(p.stock, 24);
      expect(p.imageUrl, 'https://r2/arroz.png');
      expect(p.barcode, '7702');
      expect(p.presentation, 'bolsa');
      expect(p.content, '500g');
      expect(p.isAvailable, isTrue);
    });
  });
}
