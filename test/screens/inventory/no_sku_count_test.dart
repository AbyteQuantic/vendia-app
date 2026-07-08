// Spec: specs/100-completar-skus-inventario/spec.md (T-12, FR-11, AC-09)
//
// El conteo "sin SKU" (chip y vista) cuenta SOLO referencias físicas
// escaneables: excluye platos de menú (`is_menu_item`) y servicios
// (`is_service`) — un plato no se escanea en el POS. Barcode compuesto
// solo de espacios cuenta como vacío.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';

Map<String, dynamic> _p(
  String name, {
  String? barcode,
  bool menuItem = false,
  bool service = false,
}) =>
    {
      'id': name,
      'name': name,
      if (barcode != null) 'barcode': barcode,
      if (menuItem) 'is_menu_item': true,
      if (service) 'is_service': true,
    };

void main() {
  group('isMissingSkuPhysical', () {
    test('físico con barcode vacío cuenta', () {
      expect(isMissingSkuPhysical(_p('Arroz', barcode: '')), isTrue);
    });

    test('físico sin campo barcode cuenta', () {
      expect(isMissingSkuPhysical(_p('Arroz')), isTrue);
    });

    test('barcode de solo espacios cuenta como vacío', () {
      expect(isMissingSkuPhysical(_p('Arroz', barcode: '   ')), isTrue);
    });

    test('físico con barcode NO cuenta', () {
      expect(
          isMissingSkuPhysical(_p('Coca', barcode: '7702004003508')), isFalse);
    });

    test('plato de menú sin barcode NO cuenta (AC-09)', () {
      expect(
          isMissingSkuPhysical(_p('Frijoles', barcode: '', menuItem: true)),
          isFalse);
    });

    test('servicio sin barcode NO cuenta (FR-11)', () {
      expect(isMissingSkuPhysical(_p('Corte', barcode: '', service: true)),
          isFalse);
    });
  });

  test('conteo de una lista mixta: 5 platos + 6 físicas sin código → 6', () {
    final products = <Map<String, dynamic>>[
      for (var i = 0; i < 5; i++) _p('Plato $i', barcode: '', menuItem: true),
      for (var i = 0; i < 6; i++) _p('Física $i', barcode: ''),
      _p('Con código', barcode: '111'),
    ];
    expect(products.where(isMissingSkuPhysical).length, 6);
  });
}
