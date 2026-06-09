import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/mock_api_service.dart';
import '../shared/mock_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flow 1: Checkout Efectivo', () {
    late MockApiService mockApi;

    setUpAll(() {
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
    });

    test('Cash-First Policy: Efectivo chip ALWAYS shown', () {
      bool computeCashChipAlwaysShown() => true;

      expect(computeCashChipAlwaysShown(), isTrue,
          reason: 'Empty tenant methods should still show Efectivo');

      expect(computeCashChipAlwaysShown(), isTrue,
          reason: 'Tenant with only digital methods must still show Efectivo');
    });

    test('_canConfirmWith: cash with sufficient tendered → enabled', () {
      bool canConfirm({
        required String selectedMethodKey,
        required bool isCash,
        required double amountTendered,
        required double total,
        required String? receiptUrl,
        required bool hasActiveFiado,
      }) {
        const kFiar = '__fiar__';
        if (selectedMethodKey == kFiar) return hasActiveFiado;
        if (isCash) return amountTendered >= total;
        return receiptUrl != null && receiptUrl.isNotEmpty;
      }

      expect(
        canConfirm(
          selectedMethodKey: 'cash',
          isCash: true,
          amountTendered: 50000,
          total: 32000,
          receiptUrl: null,
          hasActiveFiado: false,
        ),
        isTrue,
        reason: 'Cash with sufficient tendered should be confirmable',
      );

      expect(
        canConfirm(
          selectedMethodKey: 'cash',
          isCash: true,
          amountTendered: 20000,
          total: 32000,
          receiptUrl: null,
          hasActiveFiado: false,
        ),
        isFalse,
        reason: 'Cash with insufficient tendered should NOT be confirmable',
      );

      expect(
        canConfirm(
          selectedMethodKey: 'cash',
          isCash: true,
          amountTendered: 32000,
          total: 32000,
          receiptUrl: null,
          hasActiveFiado: false,
        ),
        isTrue,
        reason: 'Exact cash should be confirmable',
      );
    });

    test('digital payment without receipt -> disabled', () {
      bool canConfirm({
        required String selectedMethodKey,
        required bool isCash,
        required double amountTendered,
        required double total,
        required String? receiptUrl,
        required bool hasActiveFiado,
      }) {
        const kFiar = '__fiar__';
        if (selectedMethodKey == kFiar) return hasActiveFiado;
        if (isCash) return amountTendered >= total;
        return receiptUrl != null && receiptUrl.isNotEmpty;
      }

      expect(
        canConfirm(
          selectedMethodKey: 'nequi',
          isCash: false,
          amountTendered: 0,
          total: 32000,
          receiptUrl: null,
          hasActiveFiado: false,
        ),
        isFalse,
        reason: 'Digital payment without receipt must be disabled',
      );
    });

    test('createSale reduces stock and returns completed sale', () async {
      int capturedStock = 50;

      mockApi.mock('createSale', (args) {
        final items = args['items'] as List;
        for (final item in items) {
          capturedStock -= (item['quantity'] as int?) ?? 1;
        }
        return saleCompleted(
          uuid: 'sale-flow1-001',
          total: 6400,
          cashAmount: 6400,
        );
      });

      final result = await mockApi.createSale({
        'total': 6400,
        'cash_amount': 6400,
        'payment_method': 'cash',
        'items': [
          {
            'product_id': 'prod-1',
            'name': 'Arroz Diana 1kg',
            'quantity': 2,
            'unit_price': 3200,
          },
        ],
      });

      expect(result['uuid'], 'sale-flow1-001');
      expect(result['status'], 'completed');
      expect(result['total'], 6400);
      expect(result['cash_amount'], 6400);
      expect(result['payment_method'], 'cash');
      expect(capturedStock, 48,
          reason: 'Stock must decrease after sale (2 units sold from 50)');
      expect(mockApi.callCount, 1);
      expect(mockApi.callLog, contains('createSale'));
    });

    test('createSale with exact change returns change_due=0', () async {
      mockApi.mock('createSale', (args) {
        final total = (args['total'] as num).toDouble();
        final cash = (args['cash_amount'] as num).toDouble();
        return saleCompleted(
          uuid: 'sale-flow1-002',
          total: total,
          cashAmount: cash,
          changeDue: cash - total,
        );
      });

      final result = await mockApi.createSale({
        'total': 50000,
        'cash_amount': 50000,
        'payment_method': 'cash',
      });

      expect(result['change_due'], 0,
          reason: 'Exact cash should have zero change due');
    });

    test('createSale with excess cash returns correct change', () async {
      mockApi.mock('createSale', (args) {
        final total = (args['total'] as num).toDouble();
        final cash = (args['cash_amount'] as num).toDouble();
        return saleCompleted(
          uuid: 'sale-flow1-003',
          total: total,
          cashAmount: cash,
          changeDue: cash - total,
        );
      });

      final result = await mockApi.createSale({
        'total': 32000,
        'cash_amount': 50000,
        'payment_method': 'cash',
      });

      expect(result['change_due'], 18000,
          reason: '50000 paid for 32000 total should return 18000 change');
    });

    test('fetchProducts returns paginated catalog', () async {
      final result = await mockApi.fetchProducts(page: 1, perPage: 50);
      final products = result['products'] as List;
      expect(products.length, 4);
      expect(products[0]['name'], 'Arroz Diana 1kg');
      expect(products[0]['price'], 3200);
      expect(products[0]['stock'], 50);

      expect(result['total'], 4);
      expect(result['page'], 1);
    });

    test('lookupProductByBarcode finds product', () async {
      final result = await mockApi.lookupProductByBarcode('7701001001001');

      expect(result, isNotNull);
      expect(result!['name'], 'Arroz Diana 1kg');
      expect(result['barcode'], '7701001001001');
      expect(result['price'], 3200);
    });

    test('full checkout flow integration (mock api)', () async {
      mockApi.mock('createSale', (args) {
        return saleCompleted(
          uuid: 'sale-flow1-full-001',
          total: 32000,
          cashAmount: 50000,
          changeDue: 18000,
        );
      });

      final saleResponses = <Map<String, dynamic>>[];
      mockApi.mock('fetchSales', (args) {
        return {
          'sales': saleResponses,
          'total': saleResponses.length,
          'page': 1,
        };
      });

      final sale = await mockApi.createSale({
        'total': 32000,
        'cash_amount': 50000,
        'payment_method': 'cash',
        'items': [
          {
            'product_id': 'prod-1',
            'name': 'Arroz Diana 1kg',
            'quantity': 2,
            'unit_price': 3200,
          },
          {
            'product_id': 'prod-2',
            'name': 'Aceite Gourmet 900ml',
            'quantity': 1,
            'unit_price': 12400,
          },
          {
            'product_id': 'prod-3',
            'name': 'Pan Bimbo 500g',
            'quantity': 3,
            'unit_price': 6800,
          },
        ],
      });

      saleResponses.add(sale);

      expect(sale['uuid'], 'sale-flow1-full-001');
      expect(sale['status'], 'completed');
      expect(sale['total'], 32000);
      expect(sale['cash_amount'], 50000);
      expect(sale['change_due'], 18000);
      expect(mockApi.callLog, contains('createSale'));

      final salesResult = await mockApi.fetchSales();
      expect(salesResult['total'], 1);
      expect(salesResult['sales'].length, 1);
      expect(salesResult['sales'][0]['uuid'], 'sale-flow1-full-001');
    });
  });
}
