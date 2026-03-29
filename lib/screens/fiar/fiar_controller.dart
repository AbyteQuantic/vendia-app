import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_customer.dart';
import '../../database/collections/local_credit.dart';
import '../../database/collections/pending_operation.dart';
import '../../database/sync/sync_service.dart';
import '../../utils/generate_id.dart';

class FiarController extends ChangeNotifier {
  final DatabaseService _db;
  final SyncService _sync;

  FiarController(this._db, this._sync);

  List<LocalCustomer> _customers = [];
  List<LocalCustomer> get customers => _filteredCustomers;

  List<LocalCredit> _credits = [];
  List<LocalCredit> get credits => _credits;

  String _filter = 'all';
  String get filter => _filter;

  bool _loading = false;
  bool get loading => _loading;

  double get totalPending => _customers.fold(0.0, (sum, c) => sum + c.balance);

  List<LocalCustomer> get _filteredCustomers {
    switch (_filter) {
      case 'pending':
        return _customers
            .where((c) => c.balance > 0 && c.totalPaid == 0)
            .toList();
      case 'partial':
        return _customers
            .where((c) => c.balance > 0 && c.totalPaid > 0)
            .toList();
      case 'paid':
        return _customers.where((c) => c.balance <= 0).toList();
      default:
        return _customers;
    }
  }

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  Future<void> loadCustomers() async {
    _loading = true;
    notifyListeners();

    _customers = await _db.getAllCustomers();
    _loading = false;
    notifyListeners();
  }

  Future<void> loadCreditsForCustomer(String customerUuid) async {
    _credits = await _db.getCreditsForCustomer(customerUuid);
    notifyListeners();
  }

  Future<LocalCustomer> createCustomer({
    required String name,
    required String phone,
  }) async {
    final customer = LocalCustomer()
      ..uuid = generateId()
      ..name = name
      ..phone = phone
      ..totalCredit = 0
      ..totalPaid = 0
      ..createdAt = DateTime.now()
      ..clientUpdatedAt = DateTime.now();

    await _db.upsertCustomer(customer);

    final op = PendingOperation()
      ..uuid = customer.uuid
      ..entity = 'customer'
      ..action = 'create'
      ..jsonData = jsonEncode(customer.toJson())
      ..clientUpdatedAt = DateTime.now()
      ..retryCount = 0
      ..createdAt = DateTime.now();

    await _sync.enqueue(op);
    await loadCustomers();
    return customer;
  }

  Future<void> createCreditSale({
    required String customerUuid,
    required String saleUuid,
    required double amount,
  }) async {
    final credit = LocalCredit()
      ..uuid = generateId()
      ..customerUuid = customerUuid
      ..saleUuid = saleUuid
      ..totalAmount = amount
      ..paidAmount = 0
      ..status = 'pending'
      ..payments = []
      ..createdAt = DateTime.now()
      ..clientUpdatedAt = DateTime.now();

    await _db.upsertCredit(credit);

    // Update customer totals
    final customer = await _db.getCustomerByUuid(customerUuid);
    if (customer != null) {
      customer
        ..totalCredit = customer.totalCredit + amount
        ..clientUpdatedAt = DateTime.now();
      await _db.upsertCustomer(customer);
    }

    final op = PendingOperation()
      ..uuid = credit.uuid
      ..entity = 'credit'
      ..action = 'create'
      ..jsonData = jsonEncode(credit.toJson())
      ..clientUpdatedAt = DateTime.now()
      ..retryCount = 0
      ..createdAt = DateTime.now();

    await _sync.enqueue(op);
  }

  Future<void> registerPayment({
    required String creditUuid,
    required double amount,
    String note = '',
  }) async {
    final credit = await _db.getCreditByUuid(creditUuid);
    if (credit == null) return;

    final paymentUuid = generateId();
    final payment = CreditPaymentEmbed()
      ..uuid = paymentUuid
      ..amount = amount
      ..paidAt = DateTime.now()
      ..note = note;

    credit.payments.add(payment);
    credit.paidAmount += amount;
    if (credit.paidAmount >= credit.totalAmount) {
      credit.status = 'paid';
    } else {
      credit.status = 'partial';
    }
    credit.clientUpdatedAt = DateTime.now();

    await _db.upsertCredit(credit);

    // Update customer totals
    final customer = await _db.getCustomerByUuid(credit.customerUuid);
    if (customer != null) {
      customer
        ..totalPaid = customer.totalPaid + amount
        ..clientUpdatedAt = DateTime.now();
      await _db.upsertCustomer(customer);
    }

    final op = PendingOperation()
      ..uuid = paymentUuid
      ..entity = 'credit_payment'
      ..action = 'create'
      ..jsonData = jsonEncode({
        'credit_uuid': creditUuid,
        'amount': amount,
        'note': note,
        'paid_at': DateTime.now().toIso8601String(),
      })
      ..clientUpdatedAt = DateTime.now()
      ..retryCount = 0
      ..createdAt = DateTime.now();

    await _sync.enqueue(op);
    await loadCreditsForCustomer(credit.customerUuid);
    await loadCustomers();
  }
}
