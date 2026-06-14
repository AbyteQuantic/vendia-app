// Spec: specs/047-offline-sync-contract/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/local_customer.dart';
import 'package:vendia_pos/database/collections/local_credit.dart';
import 'package:vendia_pos/database/sync/sync_payloads.dart';

void main() {
  group('customerSyncPayload (AC-02)', () {
    test('solo columnas reales del modelo Customer', () {
      final c = LocalCustomer()
        ..uuid = 'c-1'
        ..name = 'Doña Rosa'
        ..phone = '3001234567'
        ..email = 'rosa@x.co'
        ..totalCredit = 5000
        ..totalPaid = 1000
        ..createdAt = DateTime(2026)
        ..clientUpdatedAt = DateTime(2026);

      final p = customerSyncPayload(c);

      expect(p.keys.toSet(), {'name', 'phone', 'email'});
      // Nada de columnas inexistentes.
      expect(p.containsKey('uuid'), isFalse);
      expect(p.containsKey('total_credit'), isFalse);
      expect(p.containsKey('total_paid'), isFalse);
    });
  });

  group('creditAccountSyncPayload (AC-03)', () {
    LocalCredit credit({String sale = ''}) => LocalCredit()
      ..uuid = 'cr-1'
      ..customerUuid = 'c-1'
      ..saleUuid = sale
      ..totalAmount = 45100.0
      ..paidAmount = 100.0
      ..status = 'pending'
      ..payments = []
      ..createdAt = DateTime(2026)
      ..clientUpdatedAt = DateTime(2026);

    test('usa customer_id y montos ENTEROS', () {
      final p = creditAccountSyncPayload(credit());
      expect(p['customer_id'], 'c-1');
      expect(p['total_amount'], 45100);
      expect(p['paid_amount'], 100);
      expect(p['total_amount'], isA<int>());
      expect(p['status'], 'pending');
    });

    test('omite sale_id cuando no hay venta (nullable uuid no puede ser "")',
        () {
      final p = creditAccountSyncPayload(credit(sale: ''));
      expect(p.containsKey('sale_id'), isFalse);
    });

    test('incluye sale_id cuando sí hay venta', () {
      final p = creditAccountSyncPayload(credit(sale: 's-9'));
      expect(p['sale_id'], 's-9');
    });

    test('no envía llaves que no son columnas (uuid/payments/customer_uuid)',
        () {
      final p = creditAccountSyncPayload(credit());
      expect(p.containsKey('uuid'), isFalse);
      expect(p.containsKey('payments'), isFalse);
      expect(p.containsKey('customer_uuid'), isFalse);
    });
  });

  group('creditPaymentSyncPayload (AC-04)', () {
    test('usa credit_account_id y amount entero', () {
      final p = creditPaymentSyncPayload(
          creditAccountId: 'cr-1', amount: 2500.0, note: 'abono');
      expect(p.keys.toSet(), {'credit_account_id', 'amount', 'note'});
      expect(p['credit_account_id'], 'cr-1');
      expect(p['amount'], 2500);
      expect(p['amount'], isA<int>());
      expect(p.containsKey('credit_uuid'), isFalse);
      expect(p.containsKey('paid_at'), isFalse);
    });
  });
}
