// Implementación nativa (móvil/escritorio) de DatabaseService, respaldada
// por Isar. Seleccionada por database_service.dart en plataformas con
// `dart.library.io`. La build web usa database_service_web.dart.
//
// Importa las colecciones `_io` directamente (no la fachada) para que los
// esquemas Isar generados (`*_io.g.dart`) y las extensiones `IsarCollection`
// queden disponibles.
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'collections/local_catalog_product_io.dart';
import 'collections/local_payment_method_io.dart';
import 'collections/local_product_io.dart';
import 'collections/local_sale_io.dart';
import 'collections/local_customer_io.dart';
import 'collections/local_credit_io.dart';
import 'collections/local_table_tab_io.dart';
import 'collections/pending_operation_io.dart';
import 'sync/product_merge.dart';
import 'sync/pending_product_push.dart';
import '../utils/digital_payment_method.dart';
import '../utils/generate_id.dart';
import '../services/tax_settings_service.dart';

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
        LocalPaymentMethodSchema,
        LocalProductSchema,
        LocalSaleSchema,
        LocalTableTabSchema,
        PendingOperationSchema,
      ],
      directory: dir.path,
      name: 'vendia',
    );
  }

  /// Test-only: abre un Isar REAL en [directory]/[name] (sin path_provider) para
  /// tests de integración de la capa de persistencia. En la VM/CI hace falta
  /// bajar el core nativo (en dispositivo viene en isar_flutter_libs). Esto es
  /// lo que permite ejercitar la serialización real (donde vivía el bug del
  /// `late` reservedStock) en vez de mockear la DB.
  @visibleForTesting
  static Future<void> initForTest({
    required String directory,
    required String name,
  }) async {
    await Isar.initializeIsarCore(download: true);
    await _isar?.close();
    _isar = await Isar.open(
      [
        LocalCatalogProductSchema,
        LocalCreditSchema,
        LocalCustomerSchema,
        LocalPaymentMethodSchema,
        LocalProductSchema,
        LocalSaleSchema,
        LocalTableTabSchema,
        PendingOperationSchema,
      ],
      directory: directory,
      name: name,
    );
  }

  /// Test-only: cierra y borra el Isar de test.
  @visibleForTesting
  static Future<void> closeForTest() async {
    await _isar?.close(deleteFromDisk: true);
    _isar = null;
  }

  static const _prefKeyLastTenant = 'vendia_last_tenant_id';

  /// Wipe tenant-scoped local collections when switching to a different tenant.
  /// Compares [newTenantId] against the previously stored tenant; skips the
  /// wipe when re-logging into the same account so today's sales survive.
  ///
  /// H10 fix — `pendingOperations` is **NOT** wiped wholesale anymore.
  /// Each op carries its own `tenantId`; the queue keeps cross-tenant
  /// ops alive so the cashier doesn't lose unsynced sales / abonos
  /// when they bounce between workspaces. The sync engine filters
  /// the queue to "current tenant only" before pushing.
  Future<void> clearIfTenantChanged(String? newTenantId) async {
    if (newTenantId == null || newTenantId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getString(_prefKeyLastTenant);

    // Always record the current tenant for the next comparison
    await prefs.setString(_prefKeyLastTenant, newTenantId);

    // Same tenant → nothing to clear
    if (prev == newTenantId) return;

    // Different tenant (or first-ever login) → wipe stale tenant-
    // scoped reference data, but preserve pendingOperations
    // (filtered server-side at sync time by their own tenantId).
    await isar.writeTxn(() async {
      await isar.localProducts.clear();
      await isar.localSales.clear();
      await isar.localCustomers.clear();
      await isar.localCredits.clear();
      // pendingOperations intentionally NOT cleared — see comment above.
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

  /// Sync products from server to local Isar.
  ///
  /// H1 fix — merge no destructivo (ver [mergeServerProducts]): el servidor es
  /// la verdad para precio/stock/foto, pero `reservedStock` (reservas de mesa,
  /// concepto local) se conserva y los productos creados offline aún sin subir
  /// (registrados en [PendingProductPush]) NO se borran. Antes hacía
  /// `clear()`+`putAll(server)` y reseteaba reservas / perdía productos.
  Future<void> replaceAllProducts(List<LocalProduct> products) async {
    if (products.isEmpty) return;
    final protected = await PendingProductPush.all();
    await isar.writeTxn(() async {
      final existing = await isar.localProducts.where().findAll();
      final merged = mergeServerProducts(
        existing: existing,
        incoming: products,
        protectedUuids: protected,
      );
      await isar.localProducts.clear();
      await isar.localProducts.putAll(merged);
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

  /// TODAS las ventas sin sincronizar (sin tope). El reintento de sync debe
  /// verlas todas — antes `getRecentSales(200)` dejaba ventas viejas no
  /// sincronizadas fuera del alcance del sweep → pérdida silenciosa.
  Future<List<LocalSale>> getUnsyncedSales() async {
    return isar.localSales.filter().syncedEqualTo(false).findAll();
  }

  Future<List<LocalSale>> getSalesSince(DateTime since) async {
    return isar.localSales.filter().createdAtGreaterThan(since).findAll();
  }

  Future<void> insertSale(LocalSale sale) async {
    await isar.writeTxn(() async {
      await isar.localSales.put(sale);
    });
  }

  /// Bulk-persist sales pulled from the server in a single transaction.
  /// Replaces direct `db.isar` access from the sync layer so the Isar
  /// engine stays encapsulated (web build has no Isar — see
  /// database_service_web.dart).
  Future<void> insertSales(List<LocalSale> sales) async {
    if (sales.isEmpty) return;
    await isar.writeTxn(() async {
      for (final sale in sales) {
        await isar.localSales.put(sale);
      }
    });
  }

  /// Flip a sale's `synced` flag and persist it. Platform-agnostic
  /// replacement for the raw `db.isar.writeTxn` calls in the POS and
  /// sales-sync paths.
  Future<void> markSaleSynced(LocalSale sale) async {
    await isar.writeTxn(() async {
      sale.synced = true;
      await isar.localSales.put(sale);
    });
  }

  /// Lazy change stream over the sales collection (no payload). Used by
  /// the dashboard to refresh KPIs when any sale row changes.
  Stream<void> watchSalesLazy() {
    return isar.localSales.watchLazy(fireImmediately: false);
  }

  /// Lazy change stream over the products collection (no payload).
  Stream<void> watchProductsLazy() {
    return isar.localProducts.watchLazy(fireImmediately: false);
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

  /// Reactive list of products whose available stock is negative
  /// (`stock - reservedStock < 0`).
  ///
  /// Isar's filter API can't compare two columns against each other in a
  /// single query, so we stream the full product set and apply the predicate
  /// in Dart. The product set is bounded (typically <1000 SKUs per tenant),
  /// so the in-memory filter is cheap and runs only when Isar actually emits
  /// a change. Sorted most-negative-first so the regularization screen
  /// surfaces the worst offenders at the top.
  Stream<List<LocalProduct>> watchNegativeStockProducts() {
    return isar.localProducts
        .where()
        .watch(fireImmediately: true)
        .map((products) {
      final negatives = products
          .where((p) => (p.stock - p.reservedStock) < 0)
          .toList();
      negatives.sort((a, b) {
        final aDelta = a.stock - a.reservedStock;
        final bDelta = b.stock - b.reservedStock;
        return aDelta.compareTo(bDelta); // most negative first
      });
      return negatives;
    });
  }

  /// Reactive count of products with negative available stock.
  ///
  /// Backed by [watchNegativeStockProducts] so the banner badge and the
  /// regularization list always agree on what counts as "negative".
  Stream<int> watchNegativeStockCount() {
    return watchNegativeStockProducts().map((list) => list.length);
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

  /// Internal: must run inside an existing writeTxn. Transitions a
  /// fully-paid tab into a closed sale: records LocalSale, drains
  /// reservedStock into actual stock deduction, marks tab completed.
  /// Idempotent — caller checks pendingBalance & status first.
  Future<void> _closeTabInTxn(LocalTableTab tab) async {
    // 1) Build LocalSale for the ledger. We freeze the active VAT
    // settings onto each line right here so the mesa-flow path is
    // symmetric with the counter / fiado paths in pos_screen — every
    // sale that lands in Isar carries its own immutable IVA snapshot.
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
    await isar.localSales.put(sale);

    // 2) Aggregate quantities per product
    final byUuid = <String, int>{};
    for (final it in tab.items) {
      byUuid[it.productUuid] = (byUuid[it.productUuid] ?? 0) + it.quantity;
    }
    // 3) Transition: stock -= qty, reservedStock -= qty (lock-step)
    for (final entry in byUuid.entries) {
      final p = await isar.localProducts
          .filter()
          .uuidEqualTo(entry.key)
          .findFirst();
      if (p == null) continue;
      p.stock = (p.stock - entry.value).clamp(0, 999999);
      p.reservedStock = (p.reservedStock - entry.value).clamp(0, 999999);
      await isar.localProducts.put(p);
    }
    // 4) Mark tab completed
    tab.status = 'completed';
    tab.synced = false;
    tab.updatedAt = DateTime.now();
    await isar.localTableTabs.put(tab);
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

      // Auto-close if the new state means the tab is paid in full.
      // Server may explicitly send status=completed/paid/closed; client
      // may detect it via pending<=0 from the abonos delta. Both routes
      // converge here so manual POS abonos AND web QR payments close
      // the mesa locally and record a LocalSale.
      final paidByMath = tab.pendingBalance <= 0 && tab.grossTotal > 0;
      final paidByStatus =
          status == 'completed' || status == 'paid' || status == 'closed';
      final notYetClosed =
          tab.status != 'completed' && tab.status != 'paid';
      if (notYetClosed && (paidByMath || paidByStatus)) {
        await _closeTabInTxn(tab);
        return; // _closeTabInTxn already put() the tab
      }
      await isar.localTableTabs.put(tab);
    });
  }

  /// Closes the tab when pendingBalance <= 0 (and not already closed).
  /// Returns true if a state transition happened. Idempotent.
  Future<bool> closeTabIfPaid(String label) async {
    return isar.writeTxn(() async {
      final tab = await isar.localTableTabs
          .filter()
          .labelEqualTo(label)
          .findFirst();
      if (tab == null) return false;
      if (tab.status == 'completed' || tab.status == 'paid') return false;
      if (tab.pendingBalance > 0 || tab.grossTotal <= 0) return false;
      await _closeTabInTxn(tab);
      return true;
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

  // ── Payment methods ─────────────────────────────────────────────────────

  Future<List<LocalPaymentMethod>> getActivePaymentMethods() async {
    return isar.localPaymentMethods
        .filter()
        .isActiveEqualTo(true)
        .findAll();
  }

  Stream<List<LocalPaymentMethod>> watchActivePaymentMethods() {
    return isar.localPaymentMethods
        .filter()
        .isActiveEqualTo(true)
        .watch(fireImmediately: true);
  }

  /// Replace the entire payment-methods cache with the server snapshot.
  /// Single writeTxn keeps deletes + inserts atomic; the stream emits
  /// once with the consolidated list.
  Future<void> replaceAllPaymentMethods(
      List<LocalPaymentMethod> methods) async {
    await isar.writeTxn(() async {
      await isar.localPaymentMethods.clear();
      if (methods.isNotEmpty) {
        await isar.localPaymentMethods.putAll(methods);
      }
    });
  }

  /// Year-to-date digital revenue stream. Emits the running total in
  /// COP whenever a LocalSale row is inserted, edited or deleted.
  /// Backed by a watch on the localSales collection with an
  /// in-memory fold; for the expected volume (~18k–73k rows per
  /// year on a small Colombian shop) the scan stays under 50 ms on
  /// a Snapdragon 4xx, well below the threshold where caching would
  /// pay off. If profiling later shows otherwise, consider adding
  /// an @Index on createdAt and switching to filter().findAll().
  Stream<double> watchYearToDateDigitalRevenue({DateTime? now}) {
    final reference = now ?? DateTime.now();
    final yearStart = DateTime(reference.year, 1, 1);
    return isar.localSales
        .where()
        .watch(fireImmediately: true)
        .map((sales) {
      var sum = 0.0;
      for (final s in sales) {
        if (!s.createdAt.isAfter(yearStart) &&
            !s.createdAt.isAtSameMomentAs(yearStart)) {
          continue;
        }
        if (!isDigitalPaymentMethod(s.paymentMethod)) continue;
        sum += s.total;
      }
      return sum;
    }).distinct();
  }
}
