import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_customer.dart';
import '../../database/collections/local_credit.dart';
import '../../database/collections/pending_operation.dart';
import '../../database/sync/sync_service.dart';
import '../../database/sync/sync_payloads.dart';
import '../../services/api_service.dart';
import '../../utils/generate_id.dart';

/// Proyección de presentación: un cliente con su saldo POR SEDE, recomputado
/// desde LocalCredit (NO del denormalizado LocalCustomer.totalCredit, que es
/// tenant-wide). Inmutable — no muta LocalCustomer, así promo/eventos lo siguen
/// leyendo intacto. Spec fiado-sede (council 2026-06-24).
class CustomerWithBranchBalance {
  final LocalCustomer customer;
  final double branchCredit;
  final double branchPaid;
  const CustomerWithBranchBalance(
      this.customer, this.branchCredit, this.branchPaid);

  double get balance => branchCredit - branchPaid;
  double get totalPaid => branchPaid;
  String get name => customer.name;
  String get phone => customer.phone;
  String get uuid => customer.uuid;
}

class FiarController extends ChangeNotifier {
  final DatabaseService _db;
  final SyncService _sync;

  FiarController(this._db, this._sync);

  List<CustomerWithBranchBalance> _customers = [];
  List<CustomerWithBranchBalance> get customers => _filteredCustomers;

  List<LocalCredit> _credits = [];
  List<LocalCredit> get credits => _credits;

  String _filter = 'all';
  String get filter => _filter;

  bool _loading = false;
  bool get loading => _loading;

  double get totalPending => _customers.fold(0.0, (sum, c) => sum + c.balance);

  List<CustomerWithBranchBalance> get _filteredCustomers {
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

    // Saldo POR SEDE: agregamos desde LocalCredit filtrado por la sede activa
    // (incluye legacy branch NULL), NO desde LocalCustomer.totalCredit (que es
    // tenant-wide). getAllCustomers SIGUE devolviendo TODOS (no se filtra ahí —
    // promo/eventos lo necesitan completo). Spec fiado-sede.
    final bid = ApiService.currentBranchId;
    final custs = await _db.getAllCustomers();
    final credits = await _db.getCreditsForBranch(bid);
    final creditBy = <String, double>{};
    final paidBy = <String, double>{};
    for (final cr in credits) {
      creditBy[cr.customerUuid] = (creditBy[cr.customerUuid] ?? 0) + cr.totalAmount;
      paidBy[cr.customerUuid] = (paidBy[cr.customerUuid] ?? 0) + cr.paidAmount;
    }
    _customers = custs
        .map((c) => CustomerWithBranchBalance(
            c, creditBy[c.uuid] ?? 0, paidBy[c.uuid] ?? 0))
        .toList();
    _loading = false;
    notifyListeners();
  }

  Future<void> loadCreditsForCustomer(String customerUuid) async {
    // Filtrar por la sede activa (incluye legacy NULL) — el detalle debe cuadrar
    // con el saldo por-sede de la lista, no mostrar todos los créditos. Spec fiado-sede.
    _credits =
        await _db.getCreditsForCustomer(customerUuid, ApiService.currentBranchId);
    notifyListeners();
  }

  Future<LocalCustomer> createCustomer({
    required String name,
    required String phone,
    String email = '',
  }) async {
    final customer = LocalCustomer()
      ..uuid = generateId()
      ..name = name
      ..phone = phone
      ..email = email
      ..totalCredit = 0
      ..totalPaid = 0
      ..createdAt = DateTime.now()
      ..clientUpdatedAt = DateTime.now();

    await _db.upsertCustomer(customer);

    final op = PendingOperation()
      ..uuid = customer.uuid
      ..entity = 'customer'
      ..action = 'create'
      // Spec 047: payload con columnas reales del modelo Customer.
      ..jsonData = jsonEncode(customerSyncPayload(customer))
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
      // Captura la sede EN EL MOMENTO de la venta. NULL si single-sede → toda
      // sede (semántica legacy). Spec fiado-sede (council 2026-06-24).
      ..branchId = ApiService.currentBranchId
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
      // Spec 047 AC-05: la entidad es 'credit_account' (el backend no conoce
      // 'credit'); payload con columnas reales (customer_id, montos enteros).
      ..entity = 'credit_account'
      ..action = 'create'
      ..jsonData = jsonEncode(creditAccountSyncPayload(credit))
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
      // Spec 047 AC-04: credit_account_id + amount entero (columnas reales).
      ..jsonData = jsonEncode(creditPaymentSyncPayload(
        creditAccountId: creditUuid,
        amount: amount,
        note: note,
      ))
      ..clientUpdatedAt = DateTime.now()
      ..retryCount = 0
      ..createdAt = DateTime.now();

    await _sync.enqueue(op);
    await loadCreditsForCustomer(credit.customerUuid);
    await loadCustomers();
  }
}
