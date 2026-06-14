// Spec: specs/047-offline-sync-contract/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/local_product.dart';
import 'package:vendia_pos/database/sync/product_merge.dart';

LocalProduct prod(String uuid, {int stock = 10, int reserved = 0, double price = 1000}) =>
    LocalProduct()
      ..uuid = uuid
      ..name = 'P-$uuid'
      ..price = price
      ..stock = stock
      ..reservedStock = reserved
      ..isAvailable = true
      ..requiresContainer = false
      ..containerPrice = 0
      ..clientUpdatedAt = DateTime(2026, 1, 1);

void main() {
  group('mergeServerProducts — pull no destructivo', () {
    test('preserva reservedStock local al refrescar desde el servidor', () {
      final existing = [prod('a', stock: 10, reserved: 3)];
      // El servidor manda el mismo producto con reserved_stock 0 (no lo sabe).
      final incoming = [prod('a', stock: 10, reserved: 0, price: 1200)];

      final merged = mergeServerProducts(existing: existing, incoming: incoming);

      expect(merged.length, 1);
      // El precio del servidor gana…
      expect(merged.first.price, 1200);
      // …pero la reserva local de la mesa NO se pierde.
      expect(merged.first.reservedStock, 3);
      // availableStock = 10 - 3 = 7 (no sobreventa).
      expect(merged.first.availableStock, 7);
    });

    test('elimina productos que el servidor ya no tiene (borrados)', () {
      final existing = [prod('a'), prod('viejo')];
      final incoming = [prod('a')];

      final merged = mergeServerProducts(existing: existing, incoming: incoming);

      expect(merged.map((p) => p.uuid), ['a']);
    });

    test('protege productos creados offline aún no subidos (protectedUuids)', () {
      final existing = [prod('a'), prod('offline-1', reserved: 0)];
      final incoming = [prod('a')]; // el server no conoce offline-1 todavía

      final merged = mergeServerProducts(
        existing: existing,
        incoming: incoming,
        protectedUuids: {'offline-1'},
      );

      expect(merged.map((p) => p.uuid).toSet(), {'a', 'offline-1'});
    });

    test('dedup del payload del servidor por uuid (último gana)', () {
      final incoming = [prod('a', price: 100), prod('a', price: 200)];
      final merged = mergeServerProducts(existing: const [], incoming: incoming);
      expect(merged.length, 1);
      expect(merged.first.price, 200);
    });

    test('un producto NO protegido y ausente del server sí se elimina', () {
      final existing = [prod('a'), prod('offline-2')];
      final incoming = [prod('a')];
      final merged = mergeServerProducts(
        existing: existing,
        incoming: incoming,
        protectedUuids: {'offline-1'}, // offline-2 NO está protegido
      );
      expect(merged.map((p) => p.uuid), ['a']);
    });
  });
}
