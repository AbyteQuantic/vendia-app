// Spec: specs/084-peluqueria-salon/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/cart_item.dart';
import 'package:vendia_pos/models/product.dart';

void main() {
  Product p() =>
      const Product(id: 1, uuid: 'p1', name: 'Corte', price: 10000, stock: 0);

  test('toJson incluye employee_uuid/name solo cuando se asigna', () {
    final unassigned = CartItem(product: p(), isService: true);
    expect(unassigned.toJson().containsKey('employee_uuid'), isFalse);

    final assigned = CartItem(product: p(), isService: true)
      ..employeeUuid = 'e1'
      ..employeeName = 'Ana';
    final json = assigned.toJson();
    expect(json['employee_uuid'], 'e1');
    expect(json['employee_name'], 'Ana');
  });

  test('round-trip conserva la atribución', () {
    final original = CartItem(product: p(), isService: true)
      ..employeeUuid = 'e2'
      ..employeeName = 'Beto';
    final restored = CartItem.fromJson(original.toJson());
    expect(restored.employeeUuid, 'e2');
    expect(restored.employeeName, 'Beto');
  });
}
