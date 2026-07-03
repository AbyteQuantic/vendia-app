// Auditoría 2026-07-02 (concilio POS↔Inventario↔Kardex): causa raíz del
// caso "Águila Light no aparece en Mi Inventario sin buscarlo" — el
// producto SÍ estaba cargado (mismo dato, misma sede, misma página que el
// POS), pero la lista era plana y sin ayudas de navegación, así que
// encontrarlo a simple vista exigía scroll a ciegas. Este archivo cubre
// `groupProductsByCategory`, la función pura que agrupa el catálogo por
// categoría para acotar el barrido visual a una sección.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';

Map<String, dynamic> _product(String name, {String? category}) =>
    {'id': name, 'name': name, if (category != null) 'category': category};

void main() {
  group('groupProductsByCategory', () {
    test('agrupa productos bajo el encabezado de su categoría', () {
      final grouped = groupProductsByCategory([
        _product('Águila Light', category: 'Bebidas'),
        _product('Coca-Cola', category: 'Bebidas'),
        _product('Papas', category: 'Snacks'),
      ]);

      expect(grouped, [
        'Bebidas',
        _product('Águila Light', category: 'Bebidas'),
        _product('Coca-Cola', category: 'Bebidas'),
        'Snacks',
        _product('Papas', category: 'Snacks'),
      ]);
    });

    test('categorías ordenadas alfabéticamente', () {
      final grouped = groupProductsByCategory([
        _product('Papas', category: 'Snacks'),
        _product('Cerveza', category: 'Bebidas'),
      ]);

      final headers = grouped.whereType<String>().toList();
      expect(headers, ['Bebidas', 'Snacks']);
    });

    test('productos sin categoría (vacía o ausente) van a "Sin categoría", '
        'siempre al final', () {
      final grouped = groupProductsByCategory([
        _product('Sin cat 1'), // sin campo category
        _product('Sin cat 2', category: '   '), // solo espacios
        _product('Con cat', category: 'Aseo'),
      ]);

      final headers = grouped.whereType<String>().toList();
      expect(headers, ['Aseo', 'Sin categoría'],
          reason: '"Sin categoría" siempre al final, aunque alfabéticamente '
              'vaya antes que "Aseo"');

      final sinCatIndex = grouped.indexOf('Sin categoría');
      expect(grouped.sublist(sinCatIndex + 1), [
        _product('Sin cat 1'),
        _product('Sin cat 2', category: '   '),
      ]);
    });

    test('preserva el orden de entrada dentro de cada categoría '
        '(ya viene alfabético por nombre desde el backend)', () {
      final grouped = groupProductsByCategory([
        _product('Águila Light', category: 'Bebidas'),
        _product('Cerveza Club Colombia', category: 'Bebidas'),
        _product('Pony Malta', category: 'Bebidas'),
      ]);

      final products = grouped.whereType<Map<String, dynamic>>().toList();
      expect(products.map((p) => p['name']), [
        'Águila Light',
        'Cerveza Club Colombia',
        'Pony Malta',
      ]);
    });

    test('lista vacía → resultado vacío', () {
      expect(groupProductsByCategory([]), isEmpty);
    });

    test('un solo grupo cuando todos comparten categoría', () {
      final grouped = groupProductsByCategory([
        _product('A', category: 'Bebidas'),
        _product('B', category: 'Bebidas'),
      ]);
      expect(grouped.whereType<String>().length, 1);
      expect(grouped.whereType<Map<String, dynamic>>().length, 2);
    });
  });
}
