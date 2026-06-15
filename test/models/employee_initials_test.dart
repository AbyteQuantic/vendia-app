// Regresión: iniciales de empleado no deben reventar con nombres mal formados.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/employee.dart';

Employee emp(String name) => Employee(
      uuid: 'e1',
      name: name,
      pin: '1234',
    );

void main() {
  group('Employee.initials — robusto ante nombres raros', () {
    test('nombre normal → dos iniciales', () {
      expect(emp('Pedro Martínez').initials, 'PM');
    });
    test('doble espacio NO lanza RangeError (antes: parts[1][0] crash)', () {
      expect(emp('Pedro  Martínez').initials, 'PM');
    });
    test('espacios al inicio/fin', () {
      expect(emp('  Ana Gómez  ').initials, 'AG');
    });
    test('un solo nombre → una inicial', () {
      expect(emp('Carlos').initials, 'C');
    });
    test('nombre vacío o solo espacios → "?"', () {
      expect(emp('').initials, '?');
      expect(emp('   ').initials, '?');
    });
    test('tres o más tokens → primeras dos', () {
      expect(emp('Juan David Pérez León').initials, 'JD');
    });
  });
}
