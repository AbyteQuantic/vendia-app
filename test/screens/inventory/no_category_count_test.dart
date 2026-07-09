// Spec: specs/102-completar-categorias-inventario/spec.md (FR-01, AC-01)
//
// El conteo "sin categoría" cuenta productos con categoría vacía (o de puros
// espacios) Y sin category_id, excluyendo borradores (is_draft). Mismo patrón
// de función pura de nivel de archivo que isMissingSkuPhysical (Spec 100).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';

Map<String, dynamic> _p(
  String name, {
  String? category,
  String? categoryId,
  bool draft = false,
}) =>
    {
      'id': name,
      'name': name,
      if (category != null) 'category': category,
      if (categoryId != null) 'category_id': categoryId,
      if (draft) 'is_draft': true,
    };

void main() {
  group('isMissingCategory', () {
    test('categoría vacía y sin category_id cuenta', () {
      expect(isMissingCategory(_p('Arroz', category: '')), isTrue);
    });

    test('sin campo category cuenta', () {
      expect(isMissingCategory(_p('Arroz')), isTrue);
    });

    test('categoría de solo espacios cuenta como vacía', () {
      expect(isMissingCategory(_p('Arroz', category: '   ')), isTrue);
    });

    test('con categoría NO cuenta', () {
      expect(isMissingCategory(_p('Coca', category: 'Bebidas')), isFalse);
    });

    test('con category_id NO cuenta aunque category esté vacía (FR-01)', () {
      expect(
          isMissingCategory(_p('Coca', category: '', categoryId: 'uuid-1')),
          isFalse);
    });

    test('borrador (is_draft) NO cuenta', () {
      expect(isMissingCategory(_p('Draft', category: '', draft: true)),
          isFalse);
    });
  });

  test('conteo AC-01: 8 sin categoría + 30 con categoría → 8', () {
    final products = <Map<String, dynamic>>[
      for (var i = 0; i < 8; i++) _p('Suelto $i', category: ''),
      for (var i = 0; i < 30; i++) _p('Ok $i', category: 'Bebidas'),
      _p('Borrador', category: '', draft: true),
    ];
    expect(products.where(isMissingCategory).length, 8);
  });
}
