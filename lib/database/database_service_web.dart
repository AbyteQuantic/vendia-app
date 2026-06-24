// Implementación web de DatabaseService — stub EN MEMORIA, sin Isar.
//
// Por qué existe: Isar depende de `dart:ffi` y genera esquemas con literales
// enteros de 64 bits que dart2js no puede compilar. La build web no puede
// usar el backend Isar nativo (ver web/README_WEB.md).
//
// Comportamiento DEGRADADO en web (aceptable para v1):
// - Los datos viven solo en memoria durante la sesión; un refresco del
//   navegador los pierde. NO hay persistencia offline real.
// - Las consultas y los streams reactivos funcionan dentro de la sesión,
//   alimentados por listas en memoria + StreamControllers.
// - La app web sigue siendo usable contra el backend (login, ventas en
//   línea, dashboards); lo que se pierde es el modo offline-first.
//
// La API pública refleja exactamente database_service_io.dart para que los
// ~28 consumidores compilen sin cambios.
import 'dart:async';

import 'collections/local_catalog_product.dart';
import 'collections/local_payment_method.dart';
import 'collections/local_product.dart';
import 'collections/local_sale.dart';
import 'collections/local_customer.dart';
import 'collections/local_credit.dart';
import 'collections/local_table_tab.dart';
import 'collections/pending_operation.dart';
import 'sync/product_merge.dart';
import 'sync/pending_product_push.dart';
import '../utils/digital_payment_method.dart';
import '../utils/generate_id.dart';
import '../services/tax_settings_service.dart';

class DatabaseService {
  static DatabaseService? _instance;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  // ── Almacenes en memoria ──────────────────────────────────────────────────
  final List<LocalProduct> _products = [];
  final List<LocalCatalogProduct> _catalog = [];
  final List<LocalSale> _sales = [];
  final List<LocalCustomer> _customers = [];
  final List<LocalCredit> _credits = [];
  final List<LocalTableTab> _tabs = [];
  final List<LocalPaymentMethod> _paymentMethods = [];
  final List<PendingOperation> _pendingOps = [];
  int _pendingSeq = 1;

  // ── Streams reactivos (sesión únicamente) ─────────────────────────────────
  final _productsCtrl = StreamController<void>.broadcast();
  final _salesCtrl = StreamController<void>.broadcast();
  final _tabsCtrl = StreamController<void>.broadcast();
  final _paymentMethodsCtrl = StreamController<void>.broadcast();

  void _emitProducts() {
    if (!_productsCtrl.isClosed) _productsCtrl.add(null);
  }

  void _emitSales() {
    if (!_salesCtrl.isClosed) _salesCtrl.add(null);
  }

  void _emitTabs() {
    if (!_tabsCtrl.isClosed) _tabsCtrl.add(null);
  }

  void _emitPaymentMethods() {
    if (!_paymentMethodsCtrl.isClosed) _paymentMethodsCtrl.add(null);
  }

  Future<void> init() async {
    // No-op en web: no hay base de datos persistente que abrir.
  }

  /// En web no hay persistencia entre sesiones, así que el cambio de tenant
  /// solo limpia los almacenes en memoria.
  Future<void> clearIfTenantChanged(String? newTenantId) async {
    if (newTenantId == null || newTenantId.isEmpty) return;
    _products.clear();
    _sales.clear();
    _customers.clear();
    _credits.clear();
    _emitProducts();
    _emitSales();
  }

  // ── Products ────────────────────────────────────────────────────────────

  Future<List<LocalProduct>> getAllProducts() async =>
      List<LocalProduct>.from(_products);

  Future<LocalProduct?> getProductByUuid(String uuid) async {
    for (final p in _products) {
      if (p.uuid == uuid) return p;
    }
    return null;
  }

  Future<LocalProduct?> getProductByBarcode(String barcode) async {
    for (final p in _products) {
      if (p.barcode == barcode) return p;
    }
    return null;
  }

  Future<void> upsertProduct(LocalProduct product) async {
    _products.removeWhere((p) => p.uuid == product.uuid);
    _products.add(product);
    _emitProducts();
  }

  Future<void> upsertProducts(List<LocalProduct> products) async {
    for (final product in products) {
      _products.removeWhere((p) => p.uuid == product.uuid);
      _products.add(product);
    }
    _emitProducts();
  }

  Future<void> replaceAllProducts(List<LocalProduct> products) async {
    if (products.isEmpty) return;
    // H1 fix — mismo merge no destructivo que el camino Isar (preserva
    // reservedStock y productos creados offline pendientes de subir).
    final protected = await PendingProductPush.all();
    final merged = mergeServerProducts(
      existing: List<LocalProduct>.from(_products),
      incoming: products,
      protectedUuids: protected,
    );
    _products
      ..clear()
      ..addAll(merged);
    _emitProducts();
  }

  Future<int?> adjustStock(String productUuid, int delta) async {
    final product = await getProductByUuid(productUuid);
    if (product == null) return null;
    product.stock = (product.stock + delta).clamp(0, 999999);
    _emitProducts();
    return product.stock;
  }

  Future<void> batchAdjustStock(Map<String, int> deltas) async {
    if (deltas.isEmpty) return;
    for (final entry in deltas.entries) {
      final product = await getProductByUuid(entry.key);
      if (product == null) continue;
      product.stock = (product.stock + entry.value).clamp(0, 999999);
    }
    _emitProducts();
  }

  // ── Catalog ──────────────────────────────────────────────────────────────

  Future<List<LocalCatalogProduct>> searchCatalog(String query) async {
    final lower = query.toLowerCase();
    return _catalog
        .where((p) => p.name.toLowerCase().contains(lower))
        .take(10)
        .toList();
  }

  Future<void> syncCatalog(List<LocalCatalogProduct> products) async {
    for (final p in products) {
      _catalog.removeWhere((c) =>
          c.name.toLowerCase() == p.name.toLowerCase() &&
          c.brand.toLowerCase() == p.brand.toLowerCase());
      _catalog.add(p);
    }
  }

  Future<int> getCatalogCount() async => _catalog.length;

  // ── Sales ────────────────────────────────────────────────────────────────

  Future<List<LocalSale>> getSalesToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return _sales.where((s) => s.createdAt.isAfter(startOfDay)).toList();
  }

  Future<List<LocalSale>> getRecentSales({int limit = 20}) async {
    final sorted = List<LocalSale>.from(_sales)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  Future<List<LocalSale>> getUnsyncedSales() async {
    return _sales.where((s) => !s.synced).toList();
  }

  Future<List<LocalSale>> getSalesSince(DateTime since) async {
    return _sales.where((s) => s.createdAt.isAfter(since)).toList();
  }

  Future<void> insertSale(LocalSale sale) async {
    _sales.add(sale);
    _emitSales();
  }

  Future<void> insertSales(List<LocalSale> sales) async {
    if (sales.isEmpty) return;
    _sales.addAll(sales);
    _emitSales();
  }

  Future<void> markSaleSynced(LocalSale sale) async {
    sale.synced = true;
    _emitSales();
  }

  Stream<void> watchSalesLazy() => _salesCtrl.stream;

  Stream<void> watchProductsLazy() => _productsCtrl.stream;

  Future<void> insertSaleAndDeductStock(LocalSale sale) async {
    _sales.add(sale);
    for (final item in sale.items) {
      if (item.isContainerCharge) continue;
      final product = await getProductByUuid(item.productUuid);
      if (product != null) {
        product.stock = (product.stock - item.quantity).clamp(0, 999999);
      }
    }
    _emitSales();
    _emitProducts();
  }

  // ── Customers ────────────────────────────────────────────────────────────

  Future<List<LocalCustomer>> getAllCustomers() async =>
      List<LocalCustomer>.from(_customers);

  Future<LocalCustomer?> getCustomerByUuid(String uuid) async {
    for (final c in _customers) {
      if (c.uuid == uuid) return c;
    }
    return null;
  }

  Future<void> upsertCustomer(LocalCustomer customer) async {
    _customers.removeWhere((c) => c.uuid == customer.uuid);
    _customers.add(customer);
  }

  // ── Credits ──────────────────────────────────────────────────────────────

  Future<List<LocalCredit>> getCreditsForCustomer(String customerUuid,
      [String? branchId]) async {
    final list =
        _credits.where((c) => c.customerUuid == customerUuid).toList();
    return _scopeCreditsToBranch(list, branchId);
  }

  /// Espejo de io: créditos de la sede + legacy (branchId NULL). Spec fiado-sede.
  Future<List<LocalCredit>> getCreditsForBranch(String? branchId) async {
    return _scopeCreditsToBranch(List<LocalCredit>.from(_credits), branchId);
  }

  List<LocalCredit> _scopeCreditsToBranch(
      List<LocalCredit> credits, String? branchId) {
    if (branchId == null || branchId.isEmpty) return credits;
    return credits
        .where((c) => c.branchId == null || c.branchId == branchId)
        .toList();
  }

  Future<LocalCredit?> getCreditByUuid(String uuid) async {
    for (final c in _credits) {
      if (c.uuid == uuid) return c;
    }
    return null;
  }

  Future<void> upsertCredit(LocalCredit credit) async {
    _credits.removeWhere((c) => c.uuid == credit.uuid);
    _credits.add(credit);
  }

  // ── Pending Operations ───────────────────────────────────────────────────

  Future<List<PendingOperation>> getPendingOps({int limit = 50}) async {
    final sorted = List<PendingOperation>.from(_pendingOps)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted.take(limit).toList();
  }

  Future<int> getPendingCount() async => _pendingOps.length;

  Future<void> addPendingOp(PendingOperation op) async {
    if (op.id == 0) op.id = _pendingSeq++;
    _pendingOps.add(op);
  }

  Future<void> removePendingOps(List<int> ids) async {
    _pendingOps.removeWhere((op) => ids.contains(op.id));
  }

  Future<void> incrementRetryCount(int id) async {
    for (final op in _pendingOps) {
      if (op.id == id) {
        op.retryCount++;
        return;
      }
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _productsCtrl.close();
    await _salesCtrl.close();
    await _tabsCtrl.close();
    await _paymentMethodsCtrl.close();
  }

  // ── Reactive Streams ─────────────────────────────────────────────────────

  Stream<LocalProduct?> watchProductByUuid(String uuid) async* {
    yield await getProductByUuid(uuid);
    yield* _productsCtrl.stream.asyncMap((_) => getProductByUuid(uuid));
  }

  Stream<List<LocalProduct>> watchNegativeStockProducts() async* {
    List<LocalProduct> compute() {
      final negatives =
          _products.where((p) => (p.stock - p.reservedStock) < 0).toList();
      negatives.sort((a, b) {
        final aDelta = a.stock - a.reservedStock;
        final bDelta = b.stock - b.reservedStock;
        return aDelta.compareTo(bDelta);
      });
      return negatives;
    }

    yield compute();
    yield* _productsCtrl.stream.map((_) => compute());
  }

  Stream<int> watchNegativeStockCount() =>
      watchNegativeStockProducts().map((list) => list.length);

  Stream<LocalTableTab?> watchTableTabByLabel(String label) async* {
    LocalTableTab? find() {
      for (final t in _tabs) {
        if (t.label == label) return t;
      }
      return null;
    }

    yield find();
    yield* _tabsCtrl.stream.map((_) => find());
  }

  Stream<List<LocalTableTab>> watchAllOpenTabs() async* {
    List<LocalTableTab> open() =>
        _tabs.where((t) => t.pendingBalance > 0).toList();
    yield open();
    yield* _tabsCtrl.stream.map((_) => open());
  }

  // ── Order commit ─────────────────────────────────────────────────────────

  Future<LocalTableTab> commitOrderToTab({
    required String label,
    required List<
            ({
              String productUuid,
              String productName,
              int quantity,
              double unitPrice
            })>
        lines,
  }) async {
    final byUuid = <String, int>{};
    for (final l in lines) {
      byUuid[l.productUuid] = (byUuid[l.productUuid] ?? 0) + l.quantity;
    }
    for (final entry in byUuid.entries) {
      final product = await getProductByUuid(entry.key);
      if (product == null) continue;
      final newReserved = product.reservedStock + entry.value;
      product.reservedStock =
          newReserved > product.stock ? product.stock : newReserved;
    }

    var tab = _tabs.cast<LocalTableTab?>().firstWhere(
          (t) => t!.label == label,
          orElse: () => null,
        );
    if (tab == null) {
      tab = LocalTableTab()
        ..label = label
        ..items = []
        ..grossTotal = 0
        ..abonosTotal = 0
        ..pendingBalance = 0
        ..status = 'nuevo'
        ..synced = false
        ..updatedAt = DateTime.now();
      _tabs.add(tab);
    }

    final now = DateTime.now();
    final newItems = <LocalTabItem>[
      ...tab.items,
      ...lines.map((l) => LocalTabItem()
        ..productUuid = l.productUuid
        ..productName = l.productName
        ..quantity = l.quantity
        ..unitPrice = l.unitPrice
        ..sentAt = now),
    ];
    tab.items = newItems;
    tab.grossTotal =
        newItems.fold<double>(0.0, (s, i) => s + (i.unitPrice * i.quantity));
    final pending = tab.grossTotal - tab.abonosTotal;
    tab.pendingBalance = pending < 0 ? 0 : pending;
    tab.updatedAt = now;
    tab.synced = false;
    _emitTabs();
    _emitProducts();
    return tab;
  }

  void _closeTab(LocalTableTab tab) {
    final taxSvc = TaxSettingsService.instance;
    final saleItems = tab.items.map((it) {
      final snap = taxSvc.snapshotForLine(
        unitPrice: it.unitPrice,
        quantity: it.quantity,
      );
      return SaleItemEmbed()
        ..productUuid = it.productUuid
        ..productName = it.productName
        ..quantity = it.quantity
        ..unitPrice = it.unitPrice
        ..isContainerCharge = false
        ..taxRate = snap.rate
        ..taxAmount = snap.amount
        ..isTaxInclusive = snap.inclusive;
    }).toList();
    final sale = LocalSale()
      ..uuid = tab.orderId ?? generateId()
      ..total = tab.grossTotal
      ..paymentMethod = 'multi'
      ..customerUuid = null
      ..isCreditSale = false
      ..saleOrigin = 'mesa'
      ..tableLabel = tab.label
      ..items = saleItems
      ..createdAt = DateTime.now()
      ..synced = false;
    _sales.add(sale);

    final byUuid = <String, int>{};
    for (final it in tab.items) {
      byUuid[it.productUuid] = (byUuid[it.productUuid] ?? 0) + it.quantity;
    }
    for (final entry in byUuid.entries) {
      LocalProduct? p;
      for (final candidate in _products) {
        if (candidate.uuid == entry.key) {
          p = candidate;
          break;
        }
      }
      if (p == null) continue;
      p.stock = (p.stock - entry.value).clamp(0, 999999);
      p.reservedStock = (p.reservedStock - entry.value).clamp(0, 999999);
    }
    tab.status = 'completed';
    tab.synced = false;
    tab.updatedAt = DateTime.now();
    _emitSales();
    _emitProducts();
  }

  Future<void> applyServerTabSnapshot(Map<String, dynamic> data) async {
    final label = (data['label'] as String?)?.trim();
    if (label == null || label.isEmpty) return;
    LocalTableTab? tab;
    for (final t in _tabs) {
      if (t.label == label) {
        tab = t;
        break;
      }
    }
    if (tab == null) return;
    final abonos =
        (data['abonos_total'] as num?)?.toDouble() ?? tab.abonosTotal;
    final status = (data['status'] as String?) ?? tab.status;
    tab.abonosTotal = abonos;
    final pending = tab.grossTotal - tab.abonosTotal;
    tab.pendingBalance = pending < 0 ? 0 : pending;
    tab.status = status;
    tab.sessionToken = (data['session_token'] as String?) ?? tab.sessionToken;
    tab.orderId = (data['order_id'] as String?) ?? tab.orderId;
    tab.synced = true;

    final paidByMath = tab.pendingBalance <= 0 && tab.grossTotal > 0;
    final paidByStatus =
        status == 'completed' || status == 'paid' || status == 'closed';
    final notYetClosed = tab.status != 'completed' && tab.status != 'paid';
    if (notYetClosed && (paidByMath || paidByStatus)) {
      _closeTab(tab);
    }
    _emitTabs();
  }

  Future<bool> closeTabIfPaid(String label) async {
    LocalTableTab? tab;
    for (final t in _tabs) {
      if (t.label == label) {
        tab = t;
        break;
      }
    }
    if (tab == null) return false;
    if (tab.status == 'completed' || tab.status == 'paid') return false;
    if (tab.pendingBalance > 0 || tab.grossTotal <= 0) return false;
    _closeTab(tab);
    _emitTabs();
    return true;
  }

  Future<void> releaseReservation(Map<String, int> deltas) async {
    if (deltas.isEmpty) return;
    for (final entry in deltas.entries) {
      final p = await getProductByUuid(entry.key);
      if (p == null) continue;
      final next = p.reservedStock - entry.value;
      p.reservedStock = next < 0 ? 0 : next;
    }
    _emitProducts();
  }

  Future<void> removeTabItem({
    required String label,
    required String productUuid,
    required int occurrence,
  }) async {
    LocalTableTab? tab;
    for (final t in _tabs) {
      if (t.label == label) {
        tab = t;
        break;
      }
    }
    if (tab == null) return;
    final indices = <int>[];
    for (var idx = 0; idx < tab.items.length; idx++) {
      if (tab.items[idx].productUuid == productUuid) indices.add(idx);
    }
    if (occurrence < 0 || occurrence >= indices.length) return;
    final removeIdx = indices[occurrence];
    final removed = tab.items[removeIdx];
    final newItems = List<LocalTabItem>.from(tab.items)..removeAt(removeIdx);
    tab.items = newItems;
    tab.grossTotal =
        newItems.fold<double>(0.0, (s, i) => s + (i.unitPrice * i.quantity));
    final pending = tab.grossTotal - tab.abonosTotal;
    tab.pendingBalance = pending < 0 ? 0 : pending;
    tab.updatedAt = DateTime.now();
    tab.synced = false;

    final p = await getProductByUuid(productUuid);
    if (p != null) {
      final next = p.reservedStock - removed.quantity;
      p.reservedStock = next < 0 ? 0 : next;
    }
    _emitTabs();
    _emitProducts();
  }

  // ── Payment methods ──────────────────────────────────────────────────────

  Future<List<LocalPaymentMethod>> getActivePaymentMethods() async {
    return _paymentMethods.where((m) => m.isActive).toList();
  }

  Stream<List<LocalPaymentMethod>> watchActivePaymentMethods() async* {
    List<LocalPaymentMethod> active() =>
        _paymentMethods.where((m) => m.isActive).toList();
    yield active();
    yield* _paymentMethodsCtrl.stream.map((_) => active());
  }

  Future<void> replaceAllPaymentMethods(
      List<LocalPaymentMethod> methods) async {
    _paymentMethods
      ..clear()
      ..addAll(methods);
    _emitPaymentMethods();
  }

  Stream<double> watchYearToDateDigitalRevenue({DateTime? now}) async* {
    final reference = now ?? DateTime.now();
    final yearStart = DateTime(reference.year, 1, 1);
    double compute() {
      var sum = 0.0;
      for (final s in _sales) {
        if (!s.createdAt.isAfter(yearStart) &&
            !s.createdAt.isAtSameMomentAs(yearStart)) {
          continue;
        }
        if (!isDigitalPaymentMethod(s.paymentMethod)) continue;
        sum += s.total;
      }
      return sum;
    }

    yield compute();
    yield* _salesCtrl.stream.map((_) => compute()).distinct();
  }
}
