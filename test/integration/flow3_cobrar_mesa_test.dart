import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/mock_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flow 3: Cobrar Mesa', () {
    late MockApiService mockApi;

    setUpAll(() {
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
    });

    group('OrderTicket operations', () {
      test('upsertTableTab creates a new table tab', () async {
        final result = await mockApi.upsertTableTab(
          label: 'Mesa 5',
          items: [
            {'product_id': 'prod-1', 'name': 'Arroz Diana 1kg', 'quantity': 2, 'unit_price': 3200},
          ],
          customerName: 'Don Carlos',
        );

        expect(result['label'], 'Mesa 5');
        expect(result['status'], 'open');
        expect(result['session_token'], isNotNull);
        expect(mockApi.callLog, contains('upsertTableTab'));
      });

      test('addItemsToTableTab adds items to existing tab', () async {
        final result = await mockApi.addItemsToTableTab(
          label: 'Mesa 5',
          items: [
            {'product_id': 'prod-2', 'name': 'Aceite Gourmet 900ml', 'quantity': 1, 'unit_price': 12400},
          ],
        );

        expect(result['label'], 'Mesa 5');
        expect(result['status'], 'open');
        expect(mockApi.callLog, contains('addItemsToTableTab'));
      });

      test('fetchTableTabByLabel returns null for non-existent tab', () async {
        mockApi.mock('fetchTableTabByLabel', (_) => null);

        final result = await mockApi.fetchTableTabByLabel('Mesa 99');
        expect(result, isNull);
      });

      test('fetchOpenAccounts returns list of open tabs', () async {
        final result = await mockApi.fetchOpenAccounts();
        expect(result, isEmpty);
      });

      test('removeItemFromTab removes an item', () async {
        mockApi.mock('removeItemFromTab', (args) {
          return {'status': 'ok', 'order_uuid': args['order_uuid'], 'item_id': args['item_id']};
        });

        final result = await mockApi.removeItemFromTab('order-1', 'item-1');
        expect(result['status'], 'ok');
        expect(mockApi.callLog, contains('removeItemFromTab'));
      });

      test('closeOrder closes a table tab', () async {
        mockApi.mock('closeOrder', (args) {
          return {'uuid': args['uuid'], 'status': 'closed', 'payment_method': args['payment_method']};
        });

        final result = await mockApi.closeOrder('order-1', 'cash');
        expect(result['status'], 'closed');
        expect(result['payment_method'], 'cash');
      });

      test('fetchPublicTableSession retrieves live tab data', () async {
        final result = await mockApi.fetchPublicTableSession('session-token-123');
        expect(result['label'], 'Mesa 5');
        expect(result['items'].length, 1);
        expect(result['total'], 6400);
      });
    });

    group('Abonos (partial payments)', () {
      test('registerPartialPayment registers an approved abono', () async {
        final result = await mockApi.registerPartialPayment(
          orderId: 'order-1',
          amount: 30000,
          paymentMethod: 'cash',
        );

        expect(result['status'], 'approved');
        expect(result['amount'], 30000);
        expect(result['payment_method'], 'cash');
        expect(mockApi.callLog, contains('registerPartialPayment'));
      });

      test('confirmPartialPayment confirms a pending abono', () async {
        final result = await mockApi.confirmPartialPayment('payment-1');
        expect(result['status'], 'confirmed');
        expect(result['already'], false);
      });

      test('registerPartialPayment with receipt image', () async {
        final result = await mockApi.registerPartialPayment(
          orderId: 'order-1',
          amount: 25000,
          paymentMethod: 'transfer',
          receiptImageUrl: 'https://storage/receipt.jpg',
        );

        expect(result['status'], 'approved');
        expect(result['amount'], 25000);
      });

      test('abono balance math: pending = gross - abonos (clamped >= 0)', () {
        double pendingAfter(double gross, double abonos) {
          final raw = gross - abonos;
          return raw < 0 ? 0.0 : raw;
        }

        expect(pendingAfter(100000, 40000), 60000);
        expect(pendingAfter(100000, 0), 100000);
        expect(pendingAfter(100000, 100000), 0);
        expect(pendingAfter(100000, 150000), 0,
            reason: 'overpayment must clamp to 0');
      });

      test('multiple abonos accumulate correctly', () {
        double pendingAfterAbonos(double gross, List<double> abonos) {
          final total = abonos.fold(0.0, (a, b) => a + b);
          final raw = gross - total;
          return raw < 0 ? 0.0 : raw;
        }

        expect(pendingAfterAbonos(100000, [30000, 20000, 10000]), 40000);
        expect(pendingAfterAbonos(100000, [50000, 50000]), 0);
      });

      test('abono prefill priority: ISAR stream > API data > 0', () {
        double resolveRemaining({
          double? streamPendingBalance,
          num? dataRemainingBalance,
        }) {
          double prefill = 0;
          if (streamPendingBalance != null && streamPendingBalance > 0) {
            prefill = streamPendingBalance;
          }
          if (prefill <= 0) {
            prefill = dataRemainingBalance?.toDouble() ?? 0;
          }
          return prefill;
        }

        expect(resolveRemaining(streamPendingBalance: 60000, dataRemainingBalance: null), 60000,
            reason: 'Priority 1: ISAR stream wins');
        expect(resolveRemaining(streamPendingBalance: null, dataRemainingBalance: 60000), 60000,
            reason: 'Priority 2: API data fallback');
        expect(resolveRemaining(streamPendingBalance: null, dataRemainingBalance: null), 0,
            reason: 'Priority 3: both absent returns 0');
        expect(resolveRemaining(streamPendingBalance: 0, dataRemainingBalance: 50000), 50000,
            reason: 'Zero stream falls back to API data');
      });
    });

    group('Full Cobrar Mesa flow (mock integration)', () {
      test('open tab -> add items -> upsert -> close', () async {
        final openedTab = await mockApi.upsertTableTab(
          label: 'Mesa 3',
          items: [
            {'product_id': 'prod-1', 'name': 'Arroz Diana 1kg', 'quantity': 2, 'unit_price': 3200},
            {'product_id': 'prod-3', 'name': 'Pan Bimbo 500g', 'quantity': 3, 'unit_price': 6800},
          ],
        );
        expect(openedTab['status'], 'open');
        expect(openedTab['label'], 'Mesa 3');

        final withExtra = await mockApi.addItemsToTableTab(
          label: 'Mesa 3',
          items: [
            {'product_id': 'prod-2', 'name': 'Aceite Gourmet 900ml', 'quantity': 1, 'unit_price': 12400},
          ],
        );
        expect(withExtra['status'], 'open');

        final abono = await mockApi.registerPartialPayment(
          orderId: openedTab['uuid'] ?? 'tab-uuid',
          amount: 20000,
          paymentMethod: 'cash',
        );
        expect(abono['status'], 'approved');

        final closed = await mockApi.closeOrder(openedTab['uuid'] ?? 'tab-uuid', 'cash');
        expect(closed['status'], 'closed');

        expect(mockApi.callLog, contains('upsertTableTab'));
        expect(mockApi.callLog, contains('addItemsToTableTab'));
        expect(mockApi.callLog, contains('registerPartialPayment'));
        expect(mockApi.callLog, contains('closeOrder'));
      });

      test('tab with item deletion flow', () async {
        final tab = await mockApi.upsertTableTab(
          label: 'Mesa 2',
          items: [
            {'product_id': 'prod-1', 'name': 'Arroz Diana 1kg', 'quantity': 2, 'unit_price': 3200},
            {'product_id': 'prod-4', 'name': 'Leche Colanta 1L', 'quantity': 1, 'unit_price': 4500},
          ],
        );
        expect(tab['status'], 'open');

        final removed = await mockApi.removeItemFromTab(tab['uuid'] ?? 'tab-uuid', 'prod-4');
        expect(removed['status'], 'ok');

        final closed = await mockApi.closeOrder(tab['uuid'] ?? 'tab-uuid', 'multi');
        expect(closed['status'], 'closed');
      });

      test('tab auto-close when stream emits completed status', () {
        bool shouldAutoClose(String? status) {
          return status == 'completed' || status == 'paid';
        }

        expect(shouldAutoClose('completed'), isTrue);
        expect(shouldAutoClose('paid'), isTrue);
        expect(shouldAutoClose('open'), isFalse);
        expect(shouldAutoClose('nuevo'), isFalse);
        expect(shouldAutoClose(null), isFalse);
      });

      test('canDelete gate: only open tabs with orderId', () {
        bool canDelete({
          required String status,
          required String? orderId,
          required String serverItemId,
        }) {
          final isOpen = status == 'nuevo' || status == 'preparando' ||
              status == 'listo' || status.isEmpty;
          return isOpen && orderId != null && serverItemId.isNotEmpty;
        }

        expect(canDelete(status: 'nuevo', orderId: 'order-1', serverItemId: 'item-1'), isTrue);
        expect(canDelete(status: 'completed', orderId: 'order-1', serverItemId: 'item-1'), isFalse);
        expect(canDelete(status: 'paid', orderId: 'order-1', serverItemId: 'item-1'), isFalse);
        expect(canDelete(status: 'nuevo', orderId: null, serverItemId: 'item-1'), isFalse);
        expect(canDelete(status: 'nuevo', orderId: 'order-1', serverItemId: ''), isFalse);
      });
    });
  });
}
