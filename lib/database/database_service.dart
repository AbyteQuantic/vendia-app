import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'collections/local_catalog_product.dart';
import 'collections/local_product.dart';
import 'collections/local_sale.dart';
import 'collections/local_customer.dart';
import 'collections/local_credit.dart';
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
        LocalProductSchema,
        LocalCatalogProductSchema,
        LocalSaleSchema,
        LocalCustomerSchema,
        LocalCreditSchema,
        PendingOperationSchema,
      ],
      directory: dir.path,
      name: 'vendia',
    );
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
    if (products.isEmpty) return; // never wipe local data with empty response
    await isar.writeTxn(() async {
      await isar.localProducts.putAll(products); // unique index on uuid does upsert
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
}
