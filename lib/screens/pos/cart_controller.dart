import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../models/product.dart';
import '../../models/cart_item.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

// ── Account Context (Mostrador / Mesa / Fiado) ─────────────────────────────

enum AccountType { mostrador, mesa, fiado, mesaInmediata }

class AccountContext {
  final AccountType type;
  final String? tableLabel;   // e.g. "Mesa 3"
  final String? customerName; // e.g. "Don Carlos"
  final String? customerPhone;

  const AccountContext({
    this.type = AccountType.mostrador,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
  });

  String get tabLabel {
    switch (type) {
      case AccountType.mesa:
        return tableLabel ?? 'Mesa';
      case AccountType.mesaInmediata:
        return tableLabel ?? 'Mesa';
      case AccountType.fiado:
        return customerName ?? 'Fiado';
      case AccountType.mostrador:
        return '';
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'tableLabel': tableLabel,
        'customerName': customerName,
        'customerPhone': customerPhone,
      };

  factory AccountContext.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'mostrador';
    return AccountContext(
      type: AccountType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => AccountType.mostrador,
      ),
      tableLabel: json['tableLabel'] as String?,
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
    );
  }
}

// ── Cart Controller ─────────────────────────────────────────────────────────

class CartController extends ChangeNotifier {
  static const int _cartCount = 10;
  static const String _storageKey = 'vendia_carts';
  static const String _contextKey = 'vendia_cart_contexts';

  final List<List<CartItem>> _carts = List.generate(_cartCount, (_) => []);
  final List<AccountContext> _contexts =
      List.generate(_cartCount, (_) => const AccountContext());

  int _activeIndex = 0;
  String _search = '';
  List<Product> _products = [];
  bool _productsLoaded = false;

  CartController() {
    _restoreCarts();
    _loadProducts();
  }

  // Mock products carry explicit uuids so addProduct's uuid-based dedupe
  // distinguishes them. Empty-uuid mocks collapse every distinct line
  // into one because the existence check keys on product.uuid.
  static final List<Product> mockProducts = [
    const Product(
        id: 1,
        uuid: 'mock-gaseosa-cola-350ml',
        name: 'Gaseosa Cola 350ml',
        price: 2500,
        stock: 50,
        requiresContainer: true,
        containerPrice: 500),
    const Product(
        id: 2,
        uuid: 'mock-agua-cristal-500ml',
        name: 'Agua Cristal 500ml',
        price: 1800,
        stock: 80),
    const Product(
        id: 3,
        uuid: 'mock-papas-margarita-80g',
        name: 'Papas Margarita 80g',
        price: 3200,
        stock: 30),
    const Product(
        id: 4,
        uuid: 'mock-arroz-diana-500g',
        name: 'Arroz Diana 500g',
        price: 2900,
        stock: 100),
    const Product(
        id: 5,
        uuid: 'mock-aceite-girasol-250ml',
        name: 'Aceite Girasol 250ml',
        price: 6500,
        stock: 20),
  ];

  Future<void> _loadProducts() async {
    try {
      final db = DatabaseService.instance;
      // Load local first (instant)
      final local = await db.getAllProducts();
      _products = local.map(_localToProduct).toList();
      _productsLoaded = true;
      notifyListeners();

      // Then pull from server and replace local
      try {
        final api = ApiService(AuthService());
        final res = await api.fetchProducts(page: 1, perPage: 100);
        final data = res['data'] as List? ?? [];
        final serverProducts = data
            .map((e) => LocalProduct.fromJson(e as Map<String, dynamic>))
            .toList();
        await db.replaceAllProducts(serverProducts);
        _products = serverProducts.map(_localToProduct).toList();
        // Debug: log products with images
        for (final p in _products.where((p) => p.imageUrl != null && p.imageUrl!.isNotEmpty)) {
          debugPrint('[PRODUCTS] ${p.name} → ${p.imageUrl!.substring(0, p.imageUrl!.length.clamp(0, 60))}...');
        }
        debugPrint('[PRODUCTS] Loaded ${_products.length} total, ${_products.where((p) => p.imageUrl != null && p.imageUrl!.isNotEmpty).length} with images');
        notifyListeners();
      } catch (e) {
        debugPrint('[PRODUCTS] Server fetch failed: $e');
        // Keep local data if server fails
      }
    } catch (_) {
      // Fallback to mock products
    }
    _productsLoaded = true;
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

  // ── Context Getters ────────────────────────────────────────────────────────

  AccountContext get activeContext => _contexts[_activeIndex];
  AccountContext contextAt(int index) => _contexts[index];

  void setContext(AccountContext ctx) {
    _contexts[_activeIndex] = ctx;
    notifyListeners();
    _persistContexts();
  }

  void clearContextForActive() {
    _contexts[_activeIndex] = const AccountContext();
    notifyListeners();
    _persistContexts();
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  int get activeIndex => _activeIndex;

  List<CartItem> get activeCart => _carts[_activeIndex];

  List<CartItem> cart(int index) => _carts[index];

  double get activeTotal =>
      activeCart.fold(0.0, (sum, item) => sum + item.subtotal);

  String get formattedTotal {
    final int cents = activeTotal.round();
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

  int cartCount(int index) =>
      _carts[index].fold(0, (sum, item) => sum + item.quantity);

  bool get productsLoaded => _productsLoaded;
  bool get hasRealProducts => _products.isNotEmpty;
  int get productCount => _products.length;

  List<Product> get allProducts =>
      _products.isNotEmpty ? _products : mockProducts;

  List<Product> get filteredProducts {
    final base = allProducts;
    if (_search.isEmpty) return base;
    final q = _search.toLowerCase();
    return base.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  /// Add an ad-hoc service line to the cart (feature flag: enable_services).
  /// The synthetic `Product` carries the description so existing cart
  /// widgets render it like any other line; the sale payload branches
  /// on [CartItem.isService] to send `is_service=true` without a
  /// `product_id`. Each call creates a distinct line — even when the
  /// description matches — because services are inherently one-off.
  void addServiceCharge({
    required String description,
    required double unitPrice,
    int quantity = 1,
  }) {
    final cleanDesc = description.trim();
    if (cleanDesc.isEmpty || unitPrice <= 0 || quantity < 1) return;
    final synthetic = Product(
      id: -DateTime.now().microsecondsSinceEpoch,
      uuid: 'service_${DateTime.now().microsecondsSinceEpoch}',
      name: cleanDesc,
      price: unitPrice,
      stock: 999,
    );
    activeCart.add(CartItem(
      product: synthetic,
      quantity: quantity,
      isService: true,
      customDescription: cleanDesc,
      customUnitPrice: unitPrice,
    ));
    notifyListeners();
    _persistCarts();
  }

  /// Add a container charge item for a product that requires a returnable container.
  void addContainerCharge(Product product) {
    final chargeProduct = Product(
      id: -product.id,
      uuid: '${product.uuid}_container',
      name: 'Envase ${product.name}',
      price: product.containerPrice.toDouble(),
      stock: 999,
    );
    activeCart.add(CartItem(product: chargeProduct));
    notifyListeners();
    _persistCarts();
  }

  // ── Persistencia ────────────────────────────────────────────────────────────

  Future<void> _restoreCarts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int i = 0; i < _cartCount; i++) {
        final cartJson = prefs.getString('${_storageKey}_$i');
        if (cartJson != null && cartJson.isNotEmpty) {
          _carts[i] = CartItem.decodeList(cartJson);
        }
      }
      // Restore contexts
      final ctxJson = prefs.getString(_contextKey);
      if (ctxJson != null && ctxJson.isNotEmpty) {
        final list = jsonDecode(ctxJson) as List;
        for (int i = 0; i < list.length && i < _cartCount; i++) {
          _contexts[i] =
              AccountContext.fromJson(list[i] as Map<String, dynamic>);
        }
      }
      notifyListeners();
    } catch (_) {
      // Silently fail on restore — start with empty carts
    }
  }

  Future<void> _persistContexts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _contexts.map((c) => c.toJson()).toList();
      await prefs.setString(_contextKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _persistCarts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int i = 0; i < _cartCount; i++) {
        if (_carts[i].isEmpty) {
          await prefs.remove('${_storageKey}_$i');
        } else {
          await prefs.setString(
              '${_storageKey}_$i', CartItem.encodeList(_carts[i]));
        }
      }
    } catch (_) {
      // Best effort persistence
    }
  }

  // ── Mutaciones ─────────────────────────────────────────────────────────────

  void switchCart(int index) {
    assert(index >= 0 && index < _cartCount);
    _activeIndex = index;
    notifyListeners();
  }

  void addProduct(Product product) {
    final existing =
        activeCart.where((item) => item.product.uuid == product.uuid).firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      activeCart.add(CartItem(product: product));
    }
    notifyListeners();
    _persistCarts();
  }

  void increment(Product product) {
    final item =
        activeCart.where((i) => i.product.id == product.id).firstOrNull;
    if (item == null) return;
    item.quantity++;
    notifyListeners();
    _persistCarts();
  }

  void decrement(Product product) {
    final index = activeCart.indexWhere((i) => i.product.id == product.id);
    if (index == -1) return;
    if (activeCart[index].quantity <= 1) {
      activeCart.removeAt(index);
    } else {
      activeCart[index].quantity--;
    }
    notifyListeners();
    _persistCarts();
  }

  void setQuantity(Product product, int qty) {
    if (qty <= 0) {
      activeCart.removeWhere((i) => i.product.uuid == product.uuid);
    } else {
      final item =
          activeCart.where((i) => i.product.uuid == product.uuid).firstOrNull;
      if (item != null) {
        item.quantity = qty;
      } else {
        activeCart.add(CartItem(product: product, quantity: qty));
      }
    }
    notifyListeners();
    _persistCarts();
  }

  int getQuantity(Product product) {
    final item =
        activeCart.where((i) => i.product.uuid == product.uuid).firstOrNull;
    return item?.quantity ?? 0;
  }

  void clearActiveCart() {
    activeCart.clear();
    _contexts[_activeIndex] = const AccountContext();
    notifyListeners();
    _persistCarts();
    _persistContexts();
  }

  /// Clear cart items but KEEP the account context (mesa stays assigned).
  void clearCartKeepContext() {
    activeCart.clear();
    notifyListeners();
    _persistCarts();
  }

  /// Find the next empty tab (no items AND no context assigned).
  /// Returns -1 if all tabs are occupied.
  int get nextEmptyIndex {
    for (int i = 0; i < _cartCount; i++) {
      if (_carts[i].isEmpty && _contexts[i].type == AccountType.mostrador) {
        return i;
      }
    }
    return -1;
  }

  /// True if the tab at [index] has a mesa/fiado context but empty cart
  /// (i.e. it was sent to kitchen and is waiting for more orders or payment).
  bool isOccupied(int index) {
    return _carts[index].isEmpty &&
        _contexts[index].type != AccountType.mostrador;
  }

  /// Assign a fiado context to a specific tab and switch to it.
  void assignFiadoToTab(String name, String phone) {
    final target = nextEmptyIndex;
    if (target == -1) return;
    _activeIndex = target;
    _contexts[target] = AccountContext(
      type: AccountType.fiado,
      customerName: name,
      customerPhone: phone,
    );
    notifyListeners();
    _persistContexts();
  }

  void setSearch(String query) {
    _search = query;
    notifyListeners();
  }
}
