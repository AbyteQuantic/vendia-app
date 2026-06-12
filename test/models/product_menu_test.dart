// Spec: specs/043-menu-restaurante-recetas/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/product.dart';

void main() {
  group('Product — campos de menú restaurante (F043)', () {
    test('fromJson lee description, portion e is_menu_item', () {
      final p = Product.fromJson({
        'id': 7,
        'name': 'Bandeja Paisa',
        'price': 25000,
        'stock': 0,
        'category': 'Platos fuertes',
        'description': 'Frijoles, arroz, carne, chicharrón',
        'portion': 'Personal',
        'is_menu_item': true,
      });

      expect(p.name, 'Bandeja Paisa');
      expect(p.description, 'Frijoles, arroz, carne, chicharrón');
      expect(p.portion, 'Personal');
      expect(p.isMenuItem, isTrue);
    });

    test('producto normal: campos de menú quedan vacíos / false', () {
      final p = Product.fromJson({
        'id': 'uuid-1',
        'name': 'Gaseosa',
        'price': 3000,
        'stock': 10,
      });

      expect(p.description, isNull);
      expect(p.portion, isNull);
      expect(p.isMenuItem, isFalse);
    });

    test('toJson solo serializa los campos de menú cuando aplican', () {
      const dish = Product(
        id: 0,
        name: 'Limonada',
        price: 8000,
        stock: 0,
        description: 'Coco rallado',
        portion: '12 oz',
        isMenuItem: true,
      );
      final json = dish.toJson();
      expect(json['description'], 'Coco rallado');
      expect(json['portion'], '12 oz');
      expect(json['is_menu_item'], true);

      const normal = Product(id: 0, name: 'Pan', price: 500, stock: 5);
      final normalJson = normal.toJson();
      expect(normalJson.containsKey('description'), isFalse);
      expect(normalJson.containsKey('portion'), isFalse);
      expect(normalJson.containsKey('is_menu_item'), isFalse);
    });
  });
}
