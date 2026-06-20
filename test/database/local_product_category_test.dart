// Spec: specs/068-categorias-caracteristicas-producto/spec.md
//
// Contrato de sync offline: category y characteristics viajan en el toJson de
// LocalProduct (push a /sync/batch) y vuelven en fromJson (pull del catálogo).
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/local_product.dart';
import 'package:vendia_pos/database/local_product_factory.dart';

void main() {
  test('toJson incluye category y characteristics (push offline)', () {
    final p = buildSavedLocalProduct(
      uuid: 'u1',
      name: 'Gaseosa',
      price: 3000,
      stock: 5,
      category: 'Bebidas',
      characteristics: 'Sin azúcar\nMarca Nacional',
    );
    final json = p.toJson();
    expect(json['category'], 'Bebidas');
    expect(json['characteristics'], 'Sin azúcar\nMarca Nacional');
  });

  test('fromJson preserva category/characteristics (pull del catálogo)', () {
    final p = LocalProduct.fromJson({
      'id': 'u2',
      'name': 'Arroz',
      'price': 2000,
      'stock': 3,
      'category': 'Granos',
      'characteristics': 'Bulto 25kg',
      'client_updated_at': DateTime.now().toIso8601String(),
    });
    expect(p.category, 'Granos');
    expect(p.characteristics, 'Bulto 25kg');
  });

  test('productos viejos sin los campos no rompen (null retrocompatible)', () {
    final p = LocalProduct.fromJson({
      'id': 'u3',
      'name': 'Legacy',
      'price': 1000,
      'stock': 1,
      'client_updated_at': DateTime.now().toIso8601String(),
    });
    expect(p.category, isNull);
    expect(p.characteristics, isNull);
    // toJson no lanza con los campos en null.
    expect(p.toJson()['category'], isNull);
  });
}
