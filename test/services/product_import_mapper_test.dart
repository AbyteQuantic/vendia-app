// Spec: specs/027-importador-inventario/spec.md
//
// Tests para ProductImportMapper — proposeMapping + validateRow + normalizePriceCOP.
// Casos: T-10 según tasks.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/product_import_mapper.dart';

void main() {
  // ── proposeMapping ─────────────────────────────────────────────────────────

  group('ProductImportMapper.proposeMapping', () {
    // name
    test('"Producto" maps to name', () {
      final m = ProductImportMapper.proposeMapping(['Producto']);
      expect(m[0], equals('name'));
    });

    test('"Nombre" maps to name', () {
      final m = ProductImportMapper.proposeMapping(['Nombre']);
      expect(m[0], equals('name'));
    });

    test('"nombre del producto" maps to name', () {
      final m = ProductImportMapper.proposeMapping(['nombre del producto']);
      expect(m[0], equals('name'));
    });

    test('"item" maps to name', () {
      final m = ProductImportMapper.proposeMapping(['item']);
      expect(m[0], equals('name'));
    });

    test('"descripcion" (without tilde) maps to name', () {
      final m = ProductImportMapper.proposeMapping(['descripcion']);
      expect(m[0], equals('name'));
    });

    test('"descripción" (with tilde) maps to name', () {
      final m = ProductImportMapper.proposeMapping(['descripción']);
      expect(m[0], equals('name'));
    });

    test('"name" (English) maps to name', () {
      final m = ProductImportMapper.proposeMapping(['name']);
      expect(m[0], equals('name'));
    });

    // price
    test('"Precio Venta" maps to price', () {
      final m = ProductImportMapper.proposeMapping(['Precio Venta']);
      expect(m[0], equals('price'));
    });

    test('"precio" maps to price', () {
      final m = ProductImportMapper.proposeMapping(['precio']);
      expect(m[0], equals('price'));
    });

    test('"Valor" maps to price', () {
      final m = ProductImportMapper.proposeMapping(['Valor']);
      expect(m[0], equals('price'));
    });

    test('"precio público" (with tilde) maps to price', () {
      final m = ProductImportMapper.proposeMapping(['precio público']);
      expect(m[0], equals('price'));
    });

    test('"PV" maps to price', () {
      final m = ProductImportMapper.proposeMapping(['PV']);
      expect(m[0], equals('price'));
    });

    test('"price" (English) maps to price', () {
      final m = ProductImportMapper.proposeMapping(['price']);
      expect(m[0], equals('price'));
    });

    // barcode
    test('"Código de Barras" maps to barcode', () {
      final m = ProductImportMapper.proposeMapping(['Código de Barras']);
      expect(m[0], equals('barcode'));
    });

    test('"codigo de barras" (without tildes) maps to barcode', () {
      final m = ProductImportMapper.proposeMapping(['codigo de barras']);
      expect(m[0], equals('barcode'));
    });

    test('"barcode" (English) maps to barcode', () {
      final m = ProductImportMapper.proposeMapping(['barcode']);
      expect(m[0], equals('barcode'));
    });

    test('"EAN" maps to barcode', () {
      final m = ProductImportMapper.proposeMapping(['EAN']);
      expect(m[0], equals('barcode'));
    });

    test('"SKU" maps to barcode', () {
      final m = ProductImportMapper.proposeMapping(['SKU']);
      expect(m[0], equals('barcode'));
    });

    test('"referencia" maps to barcode', () {
      final m = ProductImportMapper.proposeMapping(['referencia']);
      expect(m[0], equals('barcode'));
    });

    // purchase_price
    test('"Costo" maps to purchase_price', () {
      final m = ProductImportMapper.proposeMapping(['Costo']);
      expect(m[0], equals('purchase_price'));
    });

    test('"precio compra" maps to purchase_price', () {
      final m = ProductImportMapper.proposeMapping(['precio compra']);
      expect(m[0], equals('purchase_price'));
    });

    test('"PC" maps to purchase_price', () {
      final m = ProductImportMapper.proposeMapping(['PC']);
      expect(m[0], equals('purchase_price'));
    });

    // stock
    test('"Stock" maps to stock', () {
      final m = ProductImportMapper.proposeMapping(['Stock']);
      expect(m[0], equals('stock'));
    });

    test('"inventario" maps to stock', () {
      final m = ProductImportMapper.proposeMapping(['inventario']);
      expect(m[0], equals('stock'));
    });

    test('"Cantidad" maps to stock', () {
      final m = ProductImportMapper.proposeMapping(['Cantidad']);
      expect(m[0], equals('stock'));
    });

    test('"existencias" maps to stock', () {
      final m = ProductImportMapper.proposeMapping(['existencias']);
      expect(m[0], equals('stock'));
    });

    // category
    test('"Categoría" (with tilde) maps to category', () {
      final m = ProductImportMapper.proposeMapping(['Categoría']);
      expect(m[0], equals('category'));
    });

    test('"categoria" (without tilde) maps to category', () {
      final m = ProductImportMapper.proposeMapping(['categoria']);
      expect(m[0], equals('category'));
    });

    test('"tipo" maps to category', () {
      final m = ProductImportMapper.proposeMapping(['tipo']);
      expect(m[0], equals('category'));
    });

    test('"linea" maps to category', () {
      final m = ProductImportMapper.proposeMapping(['linea']);
      expect(m[0], equals('category'));
    });

    // expiry_date
    test('"Vencimiento" maps to expiry_date', () {
      final m = ProductImportMapper.proposeMapping(['Vencimiento']);
      expect(m[0], equals('expiry_date'));
    });

    test('"fecha vencimiento" maps to expiry_date', () {
      final m = ProductImportMapper.proposeMapping(['fecha vencimiento']);
      expect(m[0], equals('expiry_date'));
    });

    test('"caduca" maps to expiry_date', () {
      final m = ProductImportMapper.proposeMapping(['caduca']);
      expect(m[0], equals('expiry_date'));
    });

    // unknown
    test('"Proveedor" (unknown) returns null', () {
      final m = ProductImportMapper.proposeMapping(['Proveedor']);
      expect(m[0], isNull);
    });

    test('"ID interno" (unknown) returns null', () {
      final m = ProductImportMapper.proposeMapping(['ID interno']);
      expect(m[0], isNull);
    });

    // multi-column
    test('typical Excel: Producto, Precio Venta, Código de Barras, Costo, Stock',
        () {
      final m = ProductImportMapper.proposeMapping(
          ['Producto', 'Precio Venta', 'Código de Barras', 'Costo', 'Stock']);
      expect(m[0], equals('name'));
      expect(m[1], equals('price'));
      expect(m[2], equals('barcode'));
      expect(m[3], equals('purchase_price'));
      expect(m[4], equals('stock'));
    });

    test('duplicate target: first header wins', () {
      final m = ProductImportMapper.proposeMapping(['Producto', 'Nombre']);
      expect(m[0], equals('name'));
      expect(m[1], isNull); // second mapping to name is discarded
    });

    test('empty headers list returns empty map', () {
      final m = ProductImportMapper.proposeMapping([]);
      expect(m, isEmpty);
    });
  });

  // ── normalizePriceCOP ──────────────────────────────────────────────────────

  group('ProductImportMapper.normalizePriceCOP', () {
    test('"1500" → 1500.0', () {
      expect(ProductImportMapper.normalizePriceCOP('1500'), equals(1500.0));
    });

    test('"\$1500" → 1500.0', () {
      expect(ProductImportMapper.normalizePriceCOP('\$1500'), equals(1500.0));
    });

    test('"1.500" (Colombian thousands separator) → 1500.0', () {
      expect(ProductImportMapper.normalizePriceCOP('1.500'), equals(1500.0));
    });

    test('"1.500,00" (European: dot=thousands, comma=decimal) → 1500.0', () {
      expect(
          ProductImportMapper.normalizePriceCOP('1.500,00'), equals(1500.0));
    });

    test('"\$ 1.500" (with space and dollar) → 1500.0', () {
      expect(
          ProductImportMapper.normalizePriceCOP('\$ 1.500'), equals(1500.0));
    });

    test('"1,500" (comma as thousands) → 1500.0', () {
      expect(ProductImportMapper.normalizePriceCOP('1,500'), equals(1500.0));
    });

    test('"1500.00" (decimal dot) → 1500.0', () {
      expect(ProductImportMapper.normalizePriceCOP('1500.00'), equals(1500.0));
    });

    test('"1500.50" (decimal) → 1500.5', () {
      expect(ProductImportMapper.normalizePriceCOP('1500.50'), equals(1500.5));
    });

    test('"1.500,50" (European format) → 1500.5', () {
      expect(
          ProductImportMapper.normalizePriceCOP('1.500,50'), equals(1500.5));
    });

    test('"2500" → 2500.0', () {
      expect(ProductImportMapper.normalizePriceCOP('2500'), equals(2500.0));
    });

    test('"abc" → null (not a number)', () {
      expect(ProductImportMapper.normalizePriceCOP('abc'), isNull);
    });

    test('"" (empty) → null', () {
      expect(ProductImportMapper.normalizePriceCOP(''), isNull);
    });

    test('"0" → null (price must be > 0)', () {
      expect(ProductImportMapper.normalizePriceCOP('0'), isNull);
    });

    test('"-100" → null (negative price)', () {
      expect(ProductImportMapper.normalizePriceCOP('-100'), isNull);
    });
  });

  // ── validateRow ────────────────────────────────────────────────────────────

  group('ProductImportMapper.validateRow', () {
    test('valid row with name and price passes', () {
      final result = ProductImportMapper.validateRow({
        'name': 'Coca Cola 350ml',
        'price': '2500',
      });
      expect(result.ok, isTrue);
    });

    test('valid row with all fields passes', () {
      final result = ProductImportMapper.validateRow({
        'name': 'Agua Cristal 600ml',
        'price': '1200',
        'barcode': '7702360001234',
        'stock': '50',
        'category': 'Bebidas',
      });
      expect(result.ok, isTrue);
    });

    test('empty name fails with reason containing "nombre"', () {
      final result =
          ProductImportMapper.validateRow({'name': '', 'price': '2500'});
      expect(result.ok, isFalse);
      expect(result.reason, contains('nombre'));
    });

    test('null name fails', () {
      final result =
          ProductImportMapper.validateRow({'name': null, 'price': '2500'});
      expect(result.ok, isFalse);
    });

    test('whitespace-only name fails', () {
      final result =
          ProductImportMapper.validateRow({'name': '   ', 'price': '2500'});
      expect(result.ok, isFalse);
    });

    test('empty price fails with reason containing "precio"', () {
      final result =
          ProductImportMapper.validateRow({'name': 'Coca Cola', 'price': ''});
      expect(result.ok, isFalse);
      expect(result.reason, contains('precio'));
    });

    test('null price fails with reason containing "precio"', () {
      final result =
          ProductImportMapper.validateRow({'name': 'Coca Cola', 'price': null});
      expect(result.ok, isFalse);
      expect(result.reason, contains('precio'));
    });

    test('price "abc" fails with reason about invalid price', () {
      final result = ProductImportMapper.validateRow(
          {'name': 'Coca Cola', 'price': 'abc'});
      expect(result.ok, isFalse);
      expect(result.reason, contains('precio'));
    });

    test('price "0" fails (must be > 0)', () {
      final result =
          ProductImportMapper.validateRow({'name': 'Coca Cola', 'price': '0'});
      expect(result.ok, isFalse);
    });

    test('price "-100" fails (negative)', () {
      final result = ProductImportMapper.validateRow(
          {'name': 'Coca Cola', 'price': '-100'});
      expect(result.ok, isFalse);
    });

    test('price in Colombian format "\$ 1.500" passes', () {
      final result = ProductImportMapper.validateRow(
          {'name': 'Coca Cola', 'price': '\$ 1.500'});
      expect(result.ok, isTrue);
    });

    test('negative stock fails with reason containing "stock"', () {
      final result = ProductImportMapper.validateRow({
        'name': 'Coca Cola',
        'price': '2500',
        'stock': '-5',
      });
      expect(result.ok, isFalse);
      expect(result.reason, contains('stock'));
    });

    test('stock "0" passes (zero is valid)', () {
      final result = ProductImportMapper.validateRow({
        'name': 'Coca Cola',
        'price': '2500',
        'stock': '0',
      });
      expect(result.ok, isTrue);
    });

    test('stock decimal "1.5" passes (rounded to 2 with warning)', () {
      final result = ProductImportMapper.validateRow({
        'name': 'Coca Cola',
        'price': '2500',
        'stock': '1.5',
      });
      expect(result.ok, isTrue);
    });

    test('stock "abc" fails with reason about stock', () {
      final result = ProductImportMapper.validateRow({
        'name': 'Coca Cola',
        'price': '2500',
        'stock': 'abc',
      });
      expect(result.ok, isFalse);
      expect(result.reason, contains('stock'));
    });

    test('missing stock field passes (defaults to 0)', () {
      final result =
          ProductImportMapper.validateRow({'name': 'Coca Cola', 'price': '2500'});
      expect(result.ok, isTrue);
    });

    test('stockHasDecimalWarning is true for decimal stock', () {
      expect(
          ProductImportMapper.stockHasDecimalWarning({'stock': '1.5'}), isTrue);
    });

    test('stockHasDecimalWarning is false for integer stock', () {
      expect(
          ProductImportMapper.stockHasDecimalWarning({'stock': '10'}), isFalse);
    });

    test('stockHasDecimalWarning is false for empty stock', () {
      expect(
          ProductImportMapper.stockHasDecimalWarning({'stock': ''}), isFalse);
    });
  });

  // ── applyMapping ───────────────────────────────────────────────────────────

  group('ProductImportMapper.applyMapping', () {
    test('applies mapping correctly', () {
      final mapping = {0: 'name', 1: 'price', 2: 'barcode'};
      final row = ['Coca Cola', '2500', '7702360001234'];
      final result = ProductImportMapper.applyMapping(row, mapping);
      expect(result['name'], equals('Coca Cola'));
      expect(result['price'], equals('2500'));
      expect(result['barcode'], equals('7702360001234'));
    });

    test('ignores null-mapped columns', () {
      final mapping = {0: 'name', 1: null, 2: 'price'};
      final row = ['Coca Cola', 'ignorar', '2500'];
      final result = ProductImportMapper.applyMapping(row, mapping);
      expect(result.containsKey('name'), isTrue);
      expect(result.containsKey('price'), isTrue);
      expect(result.length, equals(2));
    });
  });
}
