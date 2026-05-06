import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'collections/local_catalog_product.dart';
import 'collections/local_product.dart';
import 'collections/local_sale.dart';
import 'collections/local_customer.dart';
import 'collections/local_credit.dart';
import 'collections/local_table_tab.dart';
import 'collections/pending_operation.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Isar? _isar;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Isar get isar {
    if (_isar == null) {
      throw StateError('DatabaseService not initialized. Call init() first.');
    }
    return _isar!;
  }

  Future<void> init() async {
    if (_isar != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        LocalCatalogProductSchema,
        LocalCreditSchema,
        LocalCustomerSchema,
        LocalProductSchema,
        LocalSaleSchema,
        LocalTableTabSchema,
        PendingOperationSchema,
      ],
      directory: dir.path,
      name: 'vendia',
    );
  }

  static const _prefKeyLastTenant = 'vendia_last_tenant_id';

  /// Wipe tenant-scoped local collections when switching to a different tenant.
  /// Compares [newTenantId] against the previously stored tenant; skips the
  /// wipe when re-logging into the same account so today's sales survive.
  Future<void> clearIfTenantChanged(String? newTenantId) async {
    if (newTenantId == null || newTenantId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getString(_prefKeyLastTenant);

    // Always record the current tenant for the next comparison
    await prefs.setString(_prefKeyLastTenant, newTenantId);

    // Same tenant → nothing to clear
    if (prev == newTenantId) return;

    // Different tenant (or first-ever login) → wipe stale data
    await isar.writeTxn(() async {
      await isar.localProducts.clear();
      await isar.localSales.clear();
      await isar.localCustomers.clear();
      await isar.localCredits.clear();
      await isar.pendingOperations.clear();
    });
  }

  // ── Products ────────────────────────────────────────────────────────────────

  Future<List<LocalProduct>> getAllProducts() async {
    return isar.localProducts.where().findAll();
  }

  Future<LocalProduct?> getProductByUuid(String uuid) async {
    return isar.localProducts.filter().uuidEqualTo(uuid).findFirst();
  }

  Future<LocalProduct?> getProductByBarcode(String barcode) async {
    return isar.localProducts.filter().barcodeEqualTo(barcode).findFirst();
  }

  Future<void> upsertProduct(LocalProduct product) async {
    await isar.writeTxn(() async {
      final existing = await isar.localProducts
          .filter()
          .uuidEqualTo(product.uuid)
          .findFirst();
      if (existing != null) {
        product.isarId = existing.isarId;
      }
      await isar.localProducts.put(product);
    });
  }

  Future<void> upsertProducts(List<LocalProduct> products) async {
    await isar.writeTxn(() async {
      for (final product in products) {
        final existing = await isar.localProducts
            .filter()
            .uuidEqualTo(product.uuid)
            .findFirst();
        if (existing != null) {
          product.isarId = existing.isarId;
        }
      }
      await isar.localProducts.putAll(products);
    });
  }

  /// Sync products from server to local Isar (upsert by UUID).
  /// Does NOT clear existing products — prevents data loss on partial fetches.
  Future<void> replaceAllProducts(List<LocalProduct> products) async {
    if (products.isEmpty) return;
    // Deduplicate by uuid — keep the last occurrence (freshest data)
    final byUuid = <String, LocalProduct>{};
    for (final p in products) {
      byUuid[p.uuid] = p;
    }
    final unique = byUuid.values.toList();
    await isar.writeTxn(() async {
      await isar.localProducts.clear();
      await isar.localProducts.putAll(unique);
    });
  }

  // ── Stock Adjustment (Single Source of Truth) ──────────────────────────────

  /// Adjusts local stock for a product by [delta] units.
  /// Positive delta = restock (item cancelled/returned).
  /// Negative delta = deduction (item sold/reserved).
  /// Returns the new stock value, or null if product not found.
  Future<int?> adjustStock(String productUuid, int delta) async {
    return await isar.writeTxn(() async {
      final product = await isar.localProducts
          .filter()
          .uuidEqualTo(productUuid)
          .findFirst();
      if (product == null) return null;
      product.stock = (product.stock + delta).clamp(0, 999999);
      await isar.localProducts.put(product);
      return product.stock;
    });
  }

  /// Batch adjust stock for multiple products in a single transaction.
  /// [deltas] maps productUuid → delta (negative = deduct, positive = restock).
  Future<void> batchAdjustStock(Map<String, int> deltas) async {
    if (deltas.isEmpty) return;
    await isar.writeTxn(() async {
      for (final entry in deltas.entries) {
        final product = await isar.localProducts
            .filter()
            .uuidEqualTo(entry.key)
            .findFirst();
        if (product == null) continue;
        product.stock = (product.stock + entry.value).clamp(0, 999999);
        await isar.localProducts.put(product);
      }
    });
  }

  // ── Catalog (OFF cache for offline-first autocomplete) ─────────────────────

  Future<List<LocalCatalogProduct>> searchCatalog(String query) async {
    final lower = query.toLowerCase();
    return isar.localCatalogProducts
        .filter()
        .nameContains(lower, caseSensitive: false)
        .limit(10)
        .findAll();
  }

  Future<void> syncCatalog(List<LocalCatalogProduct> products) async {
    await isar.writeTxn(() async {
      // Upsert by name+brand
      for (final p in products) {
        final existing = await isar.localCatalogProducts
            .filter()
            .nameEqualTo(p.name, caseSensitive: false)
            .brandEqualTo(p.brand, caseSensitive: false)
            .findFirst();
        if (existing != null) {
          p.isarId = existing.isarId;
        }
        await isar.localCatalogProducts.put(p);
      }
    });
  }

  Future<int> getCatalogCount() async {
    return isar.localCatalogProducts.count();
  }

  // ── Sales ───────────────────────────────────────────────────────────────────

  Future<List<LocalSale>> getSalesToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return isar.localSales.filter().createdAtGreaterThan(startOfDay).findAll();
  }

  Future<List<LocalSale>> getRecentSales({int limit = 20}) async {
    return isar.localSales.where().sortByCreatedAtDesc().limit(limit).findAll();
  }

  Future<List<LocalSale>> getSalesSince(DateTime since) async {
    return isar.localSales.filter().createdAtGreaterThan(since).findAll();
  }

  Future<void> insertSale(LocalSale sale) async {
    await isar.writeTxn(() async {
      await isar.localSales.put(sale);
    });
  }

  /// Atomic: insert sale AND deduct stock from products in one Isar transaction.
  Future<void> insertSaleAndDeductStock(LocalSale sale) async {
    await isar.writeTxn(() async {
      // 1. Save the sale
      await isar.localSales.put(sale);

      // 2. Deduct stock for each item
      for (final item in sale.items) {
        if (item.isContainerCharge) continue; // skip container charges
        final product = await isar.localProducts
            .filter()
            .uuidEqualTo(item.productUuid)
            .findFirst();
        if (product != null) {
          product.stock = (product.stock - item.quantity).clamp(0, 999999);
          await isar.localProducts.put(product);
        }
      }
    });
  }

  // ── Customers ───────────────────────────────────────────────────────────────

  Future<List<LocalCustomer>> getAllCustomers() async {
    return isar.localCustomers.where().findAll();
  }

  Future<LocalCustomer?> getCustomerByUuid(String uuid) async {
    return isar.localCustomers.filter().uuidEqualTo(uuid).findFirst();
  }

  Future<void> upsertCustomer(LocalCustomer customer) async {
    await isar.writeTxn(() async {
      final existing = await isar.localCustomers
          .filter()
          .uuidEqualTo(customer.uuid)
          .findFirst();
      if (existing != null) {
        customer.isarId = existing.isarId;
      }
      await isar.localCustomers.put(customer);
    });
  }

  // ── Credits ─────────────────────────────────────────────────────────────────

  Future<List<LocalCredit>> getCreditsForCustomer(String customerUuid) async {
    return isar.localCredits
        .filter()
        .customerUuidEqualTo(customerUuid)
        .findAll();
  }

  Future<LocalCredit?> getCreditByUuid(String uuid) async {
    return isar.localCredits.filter().uuidEqualTo(uuid).findFirst();
  }

  Future<void> upsertCredit(LocalCredit credit) async {
    await isar.writeTxn(() async {
      final existing =
          await isar.localCredits.filter().uuidEqualTo(credit.uuid).findFirst();
      if (existing != null) {
        credit.isarId = existing.isarId;
      }
      await isar.localCredits.put(credit);
    });
  }

  // ── Pending Operations ──────────────────────────────────────────────────────

  Future<List<PendingOperation>> getPendingOps({int limit = 50}) async {
    return isar.pendingOperations
        .where()
        .sortByCreatedAt()
        .limit(limit)
        .findAll();
  }

  Future<int> getPendingCount() async {
    return isar.pendingOperations.count();
  }

  Future<void> addPendingOp(PendingOperation op) async {
    await isar.writeTxn(() async {
      await isar.pendingOperations.put(op);
    });
  }

  Future<void> removePendingOps(List<int> ids) async {
    await isar.writeTxn(() async {
      await isar.pendingOperations.deleteAll(ids);
    });
  }

  Future<void> incrementRetryCount(int id) async {
    await isar.writeTxn(() async {
      final op = await isar.pendingOperations.get(id);
      if (op != null) {
        op.retryCount++;
        await isar.pendingOperations.put(op);
      }
    });
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }

  // ── Reactive Streams (SSOT P0 hotfix) ───────────────────────────────────

  Stream<LocalProduct?> watchProductByUuid(String uuid) {
    return isar.localProducts
        .filter()
        .uuidEqualTo(uuid)
        .watch(fireImmediately: true)
        .map((list) => list.isEmpty ? null : list.first);
  }

  Stream<LocalTableTab?> watchTableTabByLabel(String label) {
    return isar.localTableTabs
        .filter()
        .labelEqualTo(label)
        .watch(fireImmediately: true)
        .map((list) => list.isEmpty ? null : list.first);
  }

  Stream<List<LocalTableTab>> watchAllOpenTabs() {
    return isar.localTableTabs
        .filter()
        .pendingBalanceGreaterThan(0)
        .watch(fireImmediately: true);
  }

  // ── Atomic order commit (SSOT P0 hotfix) ────────────────────────────────

  /// ATOMIC: reserves stock + appends items to LocalTableTab in ONE writeTxn.
  /// Returns the updated tab. Caller should enqueue server sync AFTER this
  /// returns successfully — never inside the transaction.
  Future<LocalTableTab> commitOrderToTab({
    required String label,
    required List<({String productUuid, String productName, int quantity, double unitPrice})> lines,
  }) async {
    return await isar.writeTxn(() async {
      // 1) Reserve stock per product (idempotent if same uuid appears twice — sums)
      final byUuid = <String, int>{};
      for (final l in lines) {
        byUuid[l.productUuid] = (byUuid[l.productUuid] ?? 0) + l.quantity;
      }
      for (final entry in byUuid.entries) {
        final product = await isar.localProducts
            .filter()
            .uuidEqualTo(entry.key)
            .findFirst();
        if (product == null) continue;
        final newReserved = product.reservedStock + entry.value;
        product.reservedStock = newReserved > product.stock ? product.stock : newReserved;
        await isar.localProducts.put(product);
      }

      // 2) Upsert LocalTableTab — APPEND items, recompute totals
      var tab = await isar.localTableTabs
          .filter()
          .labelEqualTo(label)
          .findFirst();
      tab ??= LocalTableTab()
        ..label = label
        ..items = []
        ..grossTotal = 0
        ..abonosTotal = 0
        ..pendingBalance = 0
        ..status = 'nuevo'
        ..synced = false
        ..updatedAt = DateTime.now();

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
      tab.grossTotal = newItems.fold<double>(
          0.0, (s, i) => s + (i.unitPrice * i.quantity));
      final pending = tab.grossTotal - tab.abonosTotal;
      tab.pendingBalance = pending < 0 ? 0 : pending;
      tab.updatedAt = now;
      tab.synced = false;
      await isar.localTableTabs.put(tab);
      return tab;
    });
  }

  /// Reconciliation: backend confirms tab snapshot → update local tab.
  /// Touches ONLY abonosTotal/pendingBalance/status/sessionToken/orderId/synced.
  /// NEVER touches reservedStock — that's released only on final sale.
  Future<void> applyServerTabSnapshot(Map<String, dynamic> data) async {
    final label = (data['label'] as String?)?.trim();
    if (label == null || label.isEmpty) return;
    await isar.writeTxn(() async {
      final tab = await isar.localTableTabs
          .filter()
          .labelEqualTo(label)
          .findFirst();
      if (tab == null) return;
      final abonos = (data['abonos_total'] as num?)?.toDouble() ?? tab.abonosTotal;
      final status = (data['status'] as String?) ?? tab.status;
      tab.abonosTotal = abonos;
      final pending = tab.grossTotal - tab.abonosTotal;
      tab.pendingBalance = pending < 0 ? 0 : pending;
      tab.status = status;
      tab.sessionToken = (data['session_token'] as String?) ?? tab.sessionToken;
      tab.orderId = (data['order_id'] as String?) ?? tab.orderId;
      tab.synced = true;
      await isar.localTableTabs.put(tab);
    });
  }

  /// Release reservation: called when items are removed from tab or sale closes.
  Future<void> releaseReservation(Map<String, int> deltas) async {
    if (deltas.isEmpty) return;
    await isar.writeTxn(() async {
      for (final entry in deltas.entries) {
        final p = await isar.localProducts
            .filter()
            .uuidEqualTo(entry.key)
            .findFirst();
        if (p == null) continue;
        final next = p.reservedStock - entry.value;
        p.reservedStock = next < 0 ? 0 : next;
        await isar.localProducts.put(p);
      }
    });
  }

  /// Remove the Nth occurrence of [productUuid] from the local tab
  /// and recompute totals. Used by the delete-row flow in
  /// TabReviewScreen so the stream emits immediately after backend
  /// confirms the removal. Releases the reservation for the deleted
  /// quantity.
  Future<void> removeTabItem({
    required String label,
    required String productUuid,
    required int occurrence,
  }) async {
    await isar.writeTxn(() async {
      final tab = await isar.localTableTabs
          .filter()
          .labelEqualTo(label)
          .findFirst();
      if (tab == null) return;
      final indices = <int>[];
      for (var idx = 0; idx < tab.items.length; idx++) {
        if (tab.items[idx].productUuid == productUuid) indices.add(idx);
      }
      if (occurrence < 0 || occurrence >= indices.length) return;
      final removeIdx = indices[occurrence];
      final removed = tab.items[removeIdx];
      final newItems = List<LocalTabItem>.from(tab.items)
        ..removeAt(removeIdx);
      tab.items = newItems;
      tab.grossTotal = newItems.fold<double>(
          0.0, (s, i) => s + (i.unitPrice * i.quantity));
      final pending = tab.grossTotal - tab.abonosTotal;
      tab.pendingBalance = pending < 0 ? 0 : pending;
      tab.updatedAt = DateTime.now();
      tab.synced = false;
      await isar.localTableTabs.put(tab);

      // Release the reservation for the removed quantity.
      final p = await isar.localProducts
          .filter()
          .uuidEqualTo(productUuid)
          .findFirst();
      if (p != null) {
        final next = p.reservedStock - removed.quantity;
        p.reservedStock = next < 0 ? 0 : next;
        await isar.localProducts.put(p);
      }
    });
  }
}
