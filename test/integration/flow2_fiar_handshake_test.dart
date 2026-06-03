import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/mock_api_service.dart';
import '../shared/mock_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flow 2: Fiar Handshake', () {
    late MockApiService mockApi;

    setUpAll(() {
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
    });

    group('H11 — _canConfirm gate for Fiar', () {
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

      test('Fiar + no handshake -> Confirmar DISABLED', () {
        expect(
          canConfirm(
            selectedMethodKey: '__fiar__',
            isCash: false,
            amountTendered: 0,
            total: 50000,
            receiptUrl: null,
            hasActiveFiado: false,
          ),
          isFalse,
          reason: 'H11 fix: without completed handshake, fiar must be disabled',
        );
      });

      test('Fiar + handshake aceptado -> Confirmar ENABLED', () {
        expect(
          canConfirm(
            selectedMethodKey: '__fiar__',
            isCash: false,
            amountTendered: 0,
            total: 50000,
            receiptUrl: null,
            hasActiveFiado: true,
          ),
          isTrue,
        );
      });

      test('Fiar + receipt photo does NOT bypass handshake', () {
        expect(
          canConfirm(
            selectedMethodKey: '__fiar__',
            isCash: false,
            amountTendered: 0,
            total: 50000,
            receiptUrl: 'https://example.com/receipt.jpg',
            hasActiveFiado: false,
          ),
          isFalse,
          reason: 'Receipt photo is for digital payments, does not unlock fiar',
        );
      });

      test('Cash still works regardless of fiado state', () {
        expect(
          canConfirm(
            selectedMethodKey: 'cash',
            isCash: true,
            amountTendered: 50000,
            total: 50000,
            receiptUrl: null,
            hasActiveFiado: false,
          ),
          isTrue,
        );
      });
    });

    group('One-Open-Account rule (ActiveFiadoService)', () {
      test('starts with hasActive == false', () {
        final service = _FakeActiveFiadoService();
        expect(service.hasActive, isFalse);
        expect(service.accountId, isNull);
        expect(service.customerName, isNull);
      });

      test('activate() sets hasActive = true with account details', () {
        final service = _FakeActiveFiadoService();
        service.activate(
          accountId: 'credit-1',
          customerName: 'Juan Pérez',
          customerPhone: '3001112233',
          balance: 15000,
        );

        expect(service.hasActive, isTrue);
        expect(service.accountId, 'credit-1');
        expect(service.customerName, 'Juan Pérez');
        expect(service.customerPhone, '3001112233');
        expect(service.balance, 15000);
      });

      test('activate() replaces previous active account', () {
        final service = _FakeActiveFiadoService();
        service.activate(accountId: 'credit-1', customerName: 'Juan');
        service.activate(accountId: 'credit-2', customerName: 'María');

        expect(service.accountId, 'credit-2');
        expect(service.customerName, 'María');
        expect(service.hasActive, isTrue);
      });

      test('clear() resets to inactive state', () {
        final service = _FakeActiveFiadoService();
        service.activate(accountId: 'credit-1');
        expect(service.hasActive, isTrue);

        service.clear();
        expect(service.hasActive, isFalse);
        expect(service.accountId, isNull);
      });

      test('clear() on already inactive is safe (no-op)', () {
        final service = _FakeActiveFiadoService();
        service.clear();
        expect(service.hasActive, isFalse);
      });

      test('activate + clear + reactivate cycles correctly', () {
        final service = _FakeActiveFiadoService();
        service.activate(accountId: 'credit-1', balance: 50000);
        expect(service.hasActive, isTrue);

        service.clear();
        expect(service.hasActive, isFalse);

        service.activate(accountId: 'credit-2', balance: 20000);
        expect(service.hasActive, isTrue);
        expect(service.accountId, 'credit-2');
        expect(service.balance, 20000);
      });
    });

    group('ApiService — Fiar endpoints', () {
      test('fetchCredits returns active credits list', () async {
        final result = await mockApi.fetchCredits(status: 'active');
        final credits = result['credits'] as List;
        expect(credits.length, 1);
        expect(credits[0]['customer_name'], 'Juan Pérez');
        expect(credits[0]['balance'], 15000);
      });

      test('fetchCreditsGroupedByCustomer returns grouped credits', () async {
        final result = await mockApi.fetchCreditsGroupedByCustomer();
        expect(result.length, 1);
        expect(result[0]['customer_name'], 'Juan Pérez');
        expect(result[0]['total_balance'], 15000);
      });

      test('recordCreditPayment records a payment against a credit', () async {
        final result = await mockApi.recordCreditPayment('credit-1', {
          'amount': 10000,
        });

        expect(result['status'], 'completed');
        expect(result['credit_uuid'], 'credit-1');
        expect(mockApi.callLog, contains('recordCreditPayment'));
      });

      test('appendToFiado appends sale to existing credit', () async {
        mockApi.mock('appendToFiado', (args) {
          return {
            'uuid': 'credit-1',
            'total_amount': args['total_amount'],
            'new_balance': 25000,
            'status': 'active',
          };
        });

        final result = await mockApi.appendToFiado('credit-1', totalAmount: 10000);

        expect(result['new_balance'], 25000);
        expect(result['status'], 'active');
        expect(mockApi.callLog, contains('appendToFiado'));
      });

      test('fetchCustomers returns customer data for handshake form', () async {
        final result = await mockApi.fetchCustomers();
        final customers = result['customers'] as List;
        expect(customers.length, 2);
        expect(customers[0]['name'], 'Juan Pérez');
        expect(customers[0]['phone'], '3001112233');
      });

      test('createCustomer creates new customer for fiado handshake', () async {
        mockApi.mock('createCustomer', (args) {
          return {
            'uuid': 'cust-new-001',
            'name': args['name'],
            'phone': args['phone'],
          };
        });

        final result = await mockApi.createCustomer({
          'name': 'Carlos Martínez',
          'phone': '3007778899',
        });

        expect(result['uuid'], 'cust-new-001');
        expect(result['name'], 'Carlos Martínez');
        expect(result['phone'], '3007778899');
      });
    });

    group('Full Fiar flow (mock integration)', () {
      test('new fiado handshake: create customer + append sale', () async {
        final createdCustomers = <Map<String, dynamic>>[];
        mockApi.mock('createCustomer', (args) {
          final customer = {
            'uuid': 'cust-new-002',
            'name': args['name'],
            'phone': args['phone'],
          };
          createdCustomers.add(customer);
          return customer;
        });

        mockApi.mock('createSale', (args) {
          return saleCompleted(
            uuid: 'sale-fiar-001',
            total: 25000,
            paymentMethod: 'credit',
          );
        });

        final customer = await mockApi.createCustomer({
          'name': 'Pedro Ramírez',
          'phone': '3005556677',
        });

        final sale = await mockApi.createSale({
          'total': 25000,
          'payment_method': 'credit',
          'customer_uuid': customer['uuid'],
        });

        expect(createdCustomers.length, 1);
        expect(createdCustomers[0]['name'], 'Pedro Ramírez');
        expect(sale['uuid'], 'sale-fiar-001');
        expect(sale['status'], 'completed');
        expect(sale['payment_method'], 'credit');
        expect(mockApi.callLog, contains('createCustomer'));
        expect(mockApi.callLog, contains('createSale'));
      });

      test('append to existing fiado: no handshake needed', () async {
        mockApi.mock('appendToFiado', (args) {
          return {
            'uuid': 'credit-existing-1',
            'total_amount': args['total_amount'],
            'new_balance': 35000,
            'status': 'active',
          };
        });

        final result = await mockApi.appendToFiado(
          'credit-existing-1',
          totalAmount: 15000,
        );

        expect(result['new_balance'], 35000);
        expect(result['status'], 'active');
        expect(mockApi.callCount, 1);

        final credits = await mockApi.fetchCredits(status: 'active');
        final list = credits['credits'] as List;
        expect(list.length, 1);
        expect(list[0]['balance'], 15000);
      });
    });
  });
}

class _FakeActiveFiadoService {
  String? _accountId;
  String? _customerName;
  String? _customerPhone;
  int? _balance;

  String? get accountId => _accountId;
  String? get customerName => _customerName;
  String? get customerPhone => _customerPhone;
  int? get balance => _balance;
  bool get hasActive => _accountId != null;

  void activate({
    required String accountId,
    String? customerName,
    String? customerPhone,
    int? balance,
  }) {
    _accountId = accountId;
    _customerName = customerName;
    _customerPhone = customerPhone;
    _balance = balance;
  }

  void clear() {
    if (_accountId == null) return;
    _accountId = null;
    _customerName = null;
    _customerPhone = null;
    _balance = null;
  }
}
