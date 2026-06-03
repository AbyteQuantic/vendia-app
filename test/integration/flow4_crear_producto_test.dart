import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/mock_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flow 4: Crear Producto', () {
    late MockApiService mockApi;

    setUpAll(() {
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
    });

    group('Manual product creation', () {
      test('createProduct with all fields', () async {
        mockApi.mock('createProduct', (args) {
          return {
            'id': 'prod-new-001',
            'name': args['name'],
            'price': args['price'],
            'stock': args['stock'],
            'barcode': args['barcode'],
            'presentation': args['presentation'],
            'content': args['content'],
          };
        });

        final result = await mockApi.createProduct({
          'name': 'Arroz Diana 1kg',
          'price': 3200,
          'stock': 50,
          'barcode': '7701001001001',
          'presentation': 'Bolsa',
          'content': '1kg',
        });

        expect(result['id'], 'prod-new-001');
        expect(result['name'], 'Arroz Diana 1kg');
        expect(result['price'], 3200);
        expect(result['stock'], 50);
        expect(result['barcode'], '7701001001001');
        expect(result['presentation'], 'Bolsa');
        expect(result['content'], '1kg');
        expect(mockApi.callLog, contains('createProduct'));
      });

      test('createProduct with minimum fields', () async {
        final result = await mockApi.createProduct({
          'name': 'Producto Rápido',
          'price': 5000,
        });

        expect(result['name'], 'Producto Rápido');
        expect(result['stock'], 0);
        expect(result['barcode'], '');
        expect(mockApi.callCount, 1);
      });

      test('updateProduct updates existing product', () async {
        final result = await mockApi.updateProduct('prod-1', {
          'price': 3500,
          'stock': 45,
        });

        expect(result['id'], 'prod-1');
        expect(result['price'], 3500);
        expect(result['stock'], 45);
        expect(mockApi.callLog, contains('updateProduct'));
      });

      test('lookupBarcode auto-fills product data', () async {
        final result = await mockApi.lookupBarcode('7701001001001');

        expect(result['barcode'], '7701001001001');
        expect(result['name'], 'Arroz Diana 1kg');
        expect(result['price'], 3200);
      });

      test('restockProduct adds stock quantity', () async {
        mockApi.mock('restockProduct', (args) {
          return {
            'id': args['id'],
            'quantity': args['quantity'],
            'cost': args['cost'],
            'new_stock': 80,
          };
        });

        final result = await mockApi.restockProduct('prod-1', {'quantity': 30, 'cost': 2800});
        expect(result['new_stock'], 80);
        expect(mockApi.callLog, contains('restockProduct'));
      });

      test('deleteProduct removes product', () async {
        mockApi.mock('deleteProduct', (args) => {});
        await mockApi.deleteProduct('prod-1');
        expect(mockApi.callLog, contains('deleteProduct'));
      });
    });

    group('OCR Invoice scanning (simulado)', () {
      test('scanInvoice returns parsed products from invoice image', () async {
        final result = await mockApi.scanInvoice(File('/tmp/factura.jpg'));

        final products = result['products'] as List;
        expect(products.length, 2);
        expect(products[0]['name'], 'Producto Factura 1');
        expect(products[0]['price'], 5000);
        expect(products[0]['quantity'], 2);
        expect(result['total'], 13000);
        expect(mockApi.callLog, contains('scanInvoice'));
      });

      test('scanInvoice result can be used to create products', () async {
        final scanResult = await mockApi.scanInvoice(File('/tmp/factura.jpg'));
        final products = (scanResult['products'] as List).cast<Map<String, dynamic>>();

        mockApi.mock('createProduct', (args) {
          return {
            'id': 'prod-invoice-${DateTime.now().millisecondsSinceEpoch}',
            'name': args['name'],
            'price': args['price'],
            'stock': args['stock'] ?? 1,
          };
        });

        final created = <Map<String, dynamic>>[];
        for (final p in products) {
          final product = await mockApi.createProduct({
            'name': p['name'],
            'price': p['price'],
            'stock': (p['quantity'] as num?)?.toInt() ?? 1,
          });
          created.add(product);
        }

        expect(created.length, 2);
        expect(created[0]['name'], 'Producto Factura 1');
        expect(created[0]['price'], 5000);
        expect(mockApi.callCount, 3); // scanInvoice + 2 createProduct
      });

      test('scanInvoice respects 5MB file limit validation', () {
        bool validateInvoiceSize(int fileSizeBytes) {
          const maxBytes = 5 * 1024 * 1024;
          return fileSizeBytes <= maxBytes;
        }

        expect(validateInvoiceSize(1024 * 1024), isTrue, reason: '1MB OK');
        expect(validateInvoiceSize(5 * 1024 * 1024), isTrue, reason: '5MB exact OK');
        expect(validateInvoiceSize(5 * 1024 * 1024 + 1), isFalse, reason: '5MB+1 exceeds');
      });
    });

    group('Barcode product lookup', () {
      test('lookupProductByBarcode finds existing product', () async {
        final result = await mockApi.lookupProductByBarcode('7701001001001');

        expect(result, isNotNull);
        expect(result!['name'], 'Arroz Diana 1kg');
        expect(result['barcode'], '7701001001001');
      });

      test('lookupProductByBarcode returns null for unknown barcode', () async {
        mockApi.mock('lookupProductByBarcode', (_) => null);

        final result = await mockApi.lookupProductByBarcode('0000000000000');
        expect(result, isNull);
      });

      test('create product from barcode when not found', () async {
        mockApi.mock('lookupProductByBarcode', (_) => null);
        mockApi.mock('createProduct', (args) {
          return {
            'id': 'prod-from-barcode',
            'name': args['name'],
            'barcode': args['barcode'],
            'price': args['price'],
          };
        });

        final lookup = await mockApi.lookupProductByBarcode('7709999999999');
        expect(lookup, isNull);

        final created = await mockApi.createProduct({
          'name': 'Producto Nuevo',
          'barcode': '7709999999999',
          'price': 10000,
        });

        expect(created['name'], 'Producto Nuevo');
        expect(created['barcode'], '7709999999999');
      });
    });

    group('Voice inventory', () {
      test('voiceInventory returns parsed products from audio', () async {
        final result = await mockApi.voiceInventory(
          audioBytes: Uint8List.fromList([1, 2, 3, 4]),
          mimeType: 'audio/aac',
        );

        expect(result.length, 1);
        expect(result[0]['name'], 'Producto Voz 1');
        expect(result[0]['quantity'], 5);
        expect(result[0]['unit_price'], 8000);
        expect(mockApi.callLog, contains('voiceInventory'));
      });
    });

    group('Full creation flows (mock integration)', () {
      test('manual create -> restock -> update price -> barcode lookup', () async {
        final created = await mockApi.createProduct({
          'name': 'Nuevo Producto Test',
          'price': 15000,
          'stock': 10,
        });
        expect(created['id'], isNotNull);

        await mockApi.restockProduct(created['id'], {'quantity': 20, 'cost': 12000});

        await mockApi.updateProduct(created['id'], {'price': 14500});

        final lookup = await mockApi.lookupBarcode('7700000000000');
        expect(lookup, isNotNull);

        expect(mockApi.callCount, 4);
      });

      test('invoice scan -> create all products', () async {
        final scan = await mockApi.scanInvoice(File('/tmp/invoice.jpg'));
        final items = (scan['products'] as List).cast<Map<String, dynamic>>();
        expect(items.length, 2);

        for (final item in items) {
          await mockApi.createProduct({
            'name': item['name'],
            'price': item['price'],
            'stock': item['quantity'],
          });
        }

        expect(mockApi.callCount, 3, reason: '1 scan + 2 creates');
      });
    });
  });
}
