// Spec: specs/001-insumos-recetas/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/ingredient.dart';

/// Tests del modelo Ingredient (insumo) — de/serialización y reglas
/// derivadas. Cubre AC-01 (stock y unidad) y AC-05 (bajo mínimo) del lado
/// del cliente.
void main() {
  group('Ingredient.fromJson', () {
    test('parsea un insumo completo desde el contrato de API', () {
      // Forma REAL del backend: el modelo Go embebe `BaseModel`, cuya
      // llave primaria UUID se serializa como `id` (no `uuid`).
      final json = {
        'id': '2f8c0a1e-9b3d-4f6a-8c11-aa22bb33cc44',
        'tenant_id': 'tenant-1',
        'name': 'Arroz',
        'unit': 'kg',
        'stock': 10.0,
        'min_stock': 2.0,
        'unit_cost': 3200.0,
        'expiry_date': '2026-12-31T00:00:00Z',
        'supplier_id': 'sup-1',
        'created_at': '2026-05-16T10:00:00Z',
        'updated_at': '2026-05-16T10:00:00Z',
      };

      final ing = Ingredient.fromJson(json);

      // `uuid` se toma de la llave `id` del backend.
      expect(ing.uuid, '2f8c0a1e-9b3d-4f6a-8c11-aa22bb33cc44');
      expect(ing.name, 'Arroz');
      expect(ing.unit, 'kg');
      expect(ing.stock, 10.0);
      expect(ing.minStock, 2.0);
      expect(ing.unitCost, 3200.0);
      expect(ing.expiryDate, isNotNull);
      expect(ing.supplierId, 'sup-1');
    });

    test('toma el identificador de la llave `id` del backend (BUG-5)', () {
      // Regresión: antes `fromJson` leía `json['uuid']`, que no existe
      // en la respuesta real del backend → `null as String` lanzaba un
      // TypeError que la pantalla tragaba con `catch (_)`.
      final ing = Ingredient.fromJson({
        'id': 'uuid-del-backend',
        'name': 'Pollo',
      });

      expect(ing.uuid, 'uuid-del-backend');
    });

    test('mantiene respaldo a la llave `uuid` para datos locales viejos',
        () {
      final ing = Ingredient.fromJson({
        'uuid': 'uuid-legacy',
        'name': 'Sal',
      });

      expect(ing.uuid, 'uuid-legacy');
    });

    test('lanza FormatException cuando no hay id ni uuid', () {
      expect(
        () => Ingredient.fromJson({'name': 'Sin identificador'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('aplica defaults cuando faltan campos opcionales', () {
      final ing = Ingredient.fromJson({'id': 'ing-x', 'name': 'Sal'});

      expect(ing.unit, 'unidad'); // D5 — default de unidad
      expect(ing.stock, 0);
      expect(ing.minStock, 0);
      expect(ing.unitCost, 0);
      expect(ing.expiryDate, isNull);
      expect(ing.supplierId, isNull);
    });

    test('acepta stock y costo como int del backend (num) ', () {
      final ing = Ingredient.fromJson({
        'id': 'ing-y',
        'name': 'Aceite',
        'unit': 'l',
        'stock': 5,
        'unit_cost': 12000,
      });

      expect(ing.stock, 5.0);
      expect(ing.unitCost, 12000.0);
    });
  });

  group('Ingredient.toJson', () {
    test('serializa los campos que el backend espera en POST', () {
      final ing = Ingredient(
        uuid: 'ing-1',
        name: 'Pollo',
        unit: 'kg',
        stock: 3,
        minStock: 1,
        unitCost: 9000,
      );

      final json = ing.toJson();

      // El contrato de POST /api/v1/ingredients no lleva `uuid` en el
      // cuerpo: el insumo se identifica por la URL en el PATCH.
      expect(json.containsKey('uuid'), isFalse);
      expect(json['name'], 'Pollo');
      expect(json['unit'], 'kg');
      expect(json['stock'], 3);
      expect(json['min_stock'], 1);
      expect(json['unit_cost'], 9000);
    });

    test('omite expiry_date y supplier_id cuando son nulos', () {
      final ing = Ingredient(uuid: 'ing-2', name: 'Sal', unit: 'g');
      final json = ing.toJson();

      expect(json.containsKey('expiry_date'), isFalse);
      expect(json.containsKey('supplier_id'), isFalse);
    });

    test('incluye expiry_date y supplier_id cuando están presentes', () {
      final ing = Ingredient(
        uuid: 'ing-3',
        name: 'Leche',
        unit: 'l',
        expiryDate: DateTime.utc(2026, 6, 1),
        supplierId: 'sup-9',
      );
      final json = ing.toJson();

      expect(json['supplier_id'], 'sup-9');
      expect(json['expiry_date'], startsWith('2026-06-01'));
    });
  });

  group('Ingredient — reglas derivadas', () {
    test('isLowStock es verdadero cuando stock <= minStock (AC-05)', () {
      final low = Ingredient(
        uuid: 'i', name: 'X', unit: 'kg', stock: 1, minStock: 2);
      expect(low.isLowStock, isTrue);
    });

    test('isLowStock es falso cuando hay stock suficiente', () {
      final ok = Ingredient(
        uuid: 'i', name: 'X', unit: 'kg', stock: 10, minStock: 2);
      expect(ok.isLowStock, isFalse);
    });

    test('isLowStock ignora el mínimo cuando minStock es 0', () {
      final noMin = Ingredient(
        uuid: 'i', name: 'X', unit: 'kg', stock: 0, minStock: 0);
      expect(noMin.isLowStock, isFalse);
    });

    test('unitLabel devuelve la etiqueta legible en español', () {
      expect(
        Ingredient(uuid: 'i', name: 'X', unit: 'kg').unitLabel,
        'Kilogramos',
      );
      expect(
        Ingredient(uuid: 'i', name: 'X', unit: 'unidad').unitLabel,
        'Unidades',
      );
    });

    test('copyWith devuelve una copia inmutable con el cambio aplicado', () {
      final original = Ingredient(
        uuid: 'i', name: 'Arroz', unit: 'kg', stock: 5);
      final updated = original.copyWith(stock: 9);

      expect(updated.stock, 9);
      expect(original.stock, 5); // el original no muta (Art. IX)
      expect(updated.uuid, original.uuid);
    });
  });

  group('Ingredient — unidades válidas (D5)', () {
    test('expone el enum fijo de unidades del spec', () {
      expect(
        Ingredient.validUnits,
        containsAll(<String>['unidad', 'g', 'kg', 'ml', 'l']),
      );
    });
  });
}
