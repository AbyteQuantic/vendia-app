// Regresión: un producto del servidor con name/price null NO debe abortar el
// parseo (antes lanzaba y, tragado por el catch del sync, vaciaba el catálogo).
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/local_product.dart';

void main() {
  test('fromJson con name/price null no lanza y aplica defaults seguros', () {
    final p = LocalProduct.fromJson(const {
      'id': 'p-1',
      'name': null,
      'price': null,
      'stock': 5,
    });
    expect(p.uuid, 'p-1');
    expect(p.name, '');
    expect(p.price, 0);
    expect(p.stock, 5);
  });

  test('stock/reserved/container como DOUBLE (1.0) no lanzan (server num)', () {
    final p = LocalProduct.fromJson(const {
      'id': 'p-d',
      'name': 'X',
      'price': 1000,
      'stock': 5.0,
      'reserved_stock': 2.0,
      'container_price': 300.0,
    });
    expect(p.stock, 5);
    expect(p.reservedStock, 2);
    expect(p.containerPrice, 300);
  });

  test('client_updated_at malformado no aborta el parseo (tryParse)', () {
    final p = LocalProduct.fromJson(const {
      'id': 'p-bad-date',
      'name': 'X',
      'price': 1000,
      'client_updated_at': 'no-es-fecha',
    });
    expect(p.uuid, 'p-bad-date'); // no lanzó; usó DateTime.now() de fallback
  });

  test('fromJson con campos válidos sigue funcionando', () {
    final p = LocalProduct.fromJson(const {
      'id': 'p-2',
      'name': 'Arroz',
      'price': 4200,
      'stock': 10,
      'reserved_stock': 2,
    });
    expect(p.name, 'Arroz');
    expect(p.price, 4200);
    expect(p.reservedStock, 2);
    expect(p.availableStock, 8);
  });
}
