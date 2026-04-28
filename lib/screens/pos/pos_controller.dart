import 'dart:convert';
import 'package:flutter/material.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../database/collections/local_sale.dart';
import '../../database/collections/pending_operation.dart';
import '../../database/sync/sync_service.dart';
import '../../models/product.dart';
import '../../models/cart_item.dart';
import '../../utils/generate_id.dart';

enum PosStatus {
  idle,
  loadingProducts,
  ready,
  processingPayment,
  success,
  error
}

class PosController extends ChangeNotifier {
  final DatabaseService _db;
  final SyncService _sync;

  PosController(this._db, this._sync);

  PosStatus _status = PosStatus.idle;
  PosStatus get status => _status;

  List<Product> _products = [];
  List<Product> get products => _filteredProducts;

  String _searchQuery = '';
  List<CartItem> _cart = [];
  List<CartItem> get cart => _cart;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  // ── Products (offline-first) ────────────────────────────────────────────────

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    final q = _searchQuery.toLowerCase();
    // Match against name OR barcode — when the cashier scans / types a code
    // (e.g. 8412598000775), the only fast resolution path is via the
    // products.barcode column. Without this, a barcode-driven search always
    // misses because no product name contains the digits.
    return _products.where((p) {
      if (p.name.toLowerCase().contains(q)) return true;
      final code = (p.barcode ?? '').toLowerCase();
      return code.isNotEmpty && code.contains(q);
    }).toList();
  }

  void setSearch(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  /// Load products from Isar first (instant), then pull from server in background.
  Future<void> loadProducts() async {
    _status = PosStatus.loadingProducts;
    notifyListeners();

    try {
      final localProducts = await _db.getAllProducts();
      _products = localProducts.map(_localToProduct).toList();
      _status = PosStatus.ready;
      notifyListeners();

      // Background: sync will pull fresh data from server
      _sync.syncNow();
    } catch (_) {
      if (_products.isEmpty) {
        _status = PosStatus.error;
        _errorMessage = 'No se pudieron cargar los productos.';
      }
      notifyListeners();
    }
  }

  /// Refresh products from Isar (called after sync completes).
  Future<void> refreshFromLocal() async {
    final localProducts = await _db.getAllProducts();
    _products = localProducts.map(_localToProduct).toList();
    if (_products.isNotEmpty && _status != PosStatus.processingPayment) {
      _status = PosStatus.ready;
    }
    notifyListeners();
  }

  Product _localToProduct(LocalProduct lp) => Product(
        id: lp.serverId ?? 0,
        uuid: lp.uuid,
        name: lp.name,
        price: lp.price,
        stock: lp.stock,
        imageUrl: lp.imageUrl,
        isAvailable: lp.isAvailable,
        requiresContainer: lp.requiresContainer,
        containerPrice: lp.containerPrice,
        barcode: lp.barcode,
        presentation: lp.presentation,
        content: lp.content,
      );

  // ── Cart ─────────────────────────────────────────────────────────────────────

  void addToCart(Product product) {
    final idx = _cart.indexWhere((i) => i.product.id == product.id);
    if (idx >= 0) {
      _cart[idx].quantity++;
    } else {
      _cart.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void removeFromCart(int productId) {
    _cart.removeWhere((i) => i.product.id == productId);
    notifyListeners();
  }

  void decreaseQuantity(int productId) {
    final idx = _cart.indexWhere((i) => i.product.id == productId);
    if (idx < 0) return;
    if (_cart[idx].quantity <= 1) {
      _cart.removeAt(idx);
    } else {
      _cart[idx].quantity--;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart = [];
    notifyListeners();
  }

  int get cartCount => _cart.fold(0, (sum, i) => sum + i.quantity);

  double get cartTotal => _cart.fold(0, (sum, i) => sum + i.subtotal);

  String get formattedTotal {
    final int cents = cartTotal.round();
    if (cents == 0) return '\$0';
    final String s = cents.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  // ── Sale (offline-first) ────────────────────────────────────────────────────

  /// Process sale entirely locally. UI NEVER waits for server.
  Future<bool> processSale(String paymentMethod, {String? customerUuid}) async {
    if (_cart.isEmpty) return false;

    _status = PosStatus.processingPayment;
    notifyListeners();

    try {
      final saleUuid = generateId();
      final isCreditSale = paymentMethod == 'credit';

      final saleItems = _cart.map((item) {
        return SaleItemEmbed()
          ..productUuid = item.product.uuid.isNotEmpty
              ? item.product.uuid
              : item.product.id.toString()
          ..productName = item.product.name
          ..quantity = item.quantity
          ..unitPrice = item.product.price
          ..isContainerCharge = false;
      }).toList();

      final localSale = LocalSale()
        ..uuid = saleUuid
        ..total = cartTotal
        ..paymentMethod = paymentMethod
        ..customerUuid = customerUuid
        ..isCreditSale = isCreditSale
        ..items = saleItems
        ..createdAt = DateTime.now()
        ..synced = false;

      // Atomic transaction: save sale + deduct stock
      await _db.insertSaleAndDeductStock(localSale);

      final pendingOp = PendingOperation()
        ..uuid = saleUuid
        ..entity = 'sale'
        ..action = 'create'
        ..jsonData = jsonEncode(localSale.toJson())
        ..clientUpdatedAt = DateTime.now()
        ..retryCount = 0
        ..createdAt = DateTime.now();

      await _sync.enqueue(pendingOp);

      clearCart();
      _status = PosStatus.success;
      notifyListeners();
      return true;
    } catch (_) {
      _status = PosStatus.error;
      _errorMessage = 'Error al registrar la venta.';
      notifyListeners();
      return false;
    }
  }

  void resetStatus() {
    _status = _products.isEmpty ? PosStatus.idle : PosStatus.ready;
    notifyListeners();
  }
}
