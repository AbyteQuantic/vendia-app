import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../models/product.dart';
import '../../models/cart_item.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';

// ── Account Context (Mostrador / Mesa / Fiado) ─────────────────────────────

enum AccountType { mostrador, mesa, fiado, mesaInmediata }

class AccountContext {
  final AccountType type;
  final String? tableLabel;   // e.g. "Mesa 3"
  final String? customerName; // e.g. "Don Carlos"
  final String? customerPhone;

  /// Server-side session token for this tab. Populated by
  /// [CartController.syncActiveTableTab] after a successful PUT
  /// /api/v1/tables/tab. Persisted so re-opening the app keeps
  /// the QR pointing to the same live tab.
  final String? sessionToken;

  /// Server-side order_id for the open tab. Kept alongside the
  /// session_token because the authenticated POS screens (e.g.
  /// detail view) expect an order uuid, while the public live
  /// tab page uses the token. Nullable until first sync.
  final String? orderId;

  const AccountContext({
    this.type = AccountType.mostrador,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
    this.sessionToken,
    this.orderId,
  });

  AccountContext copyWith({
    AccountType? type,
    String? tableLabel,
    String? customerName,
    String? customerPhone,
    String? sessionToken,
    String? orderId,
  }) {
    return AccountContext(
      type: type ?? this.type,
      tableLabel: tableLabel ?? this.tableLabel,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      sessionToken: sessionToken ?? this.sessionToken,
      orderId: orderId ?? this.orderId,
    );
  }

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
        'sessionToken': sessionToken,
        'orderId': orderId,
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
      sessionToken: json['sessionToken'] as String?,
      orderId: json['orderId'] as String?,
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

  // ── Background table-tab persistence ───────────────────────────
  //
  // Per-tab debounced writer. Each tab index has at most one in-
  // flight Timer. When a cashier taps "+" three times on Mesa 1
  // we only hit the backend once, 800ms after the last tap.
  // On "Enviar a mesa" / payment the caller can bypass the
  // debounce with flushTableTab(index: activeIndex).
  final Map<int, Timer> _syncTimers = {};
  static const Duration _syncDebounce = Duration(milliseconds: 800);

  /// Exposed for tests: inject a fake ApiService / AuthService so
  /// the provider tests don't need a live backend. Production
  /// callers keep using the default constructor.
  final ApiService? apiOverride;

  CartController({this.apiOverride}) {
    _restoreCarts();
    _loadProducts();
  }

  @override
  void dispose() {
    for (final t in _syncTimers.values) {
      t.cancel();
    }
    _syncTimers.clear();
    super.dispose();
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
    // If the cashier just assigned a table AFTER adding products
    // (common flow: pick items, then decide "llévalo a la Mesa 3"),
    // push the cart to the backend so the QR is immediately live.
    _scheduleTableTabSync(_activeIndex);
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
    _scheduleTableTabSync(_activeIndex);
  }

  void increment(Product product) {
    final item =
        activeCart.where((i) => i.product.id == product.id).firstOrNull;
    if (item == null) return;
    item.quantity++;
    notifyListeners();
    _persistCarts();
    _scheduleTableTabSync(_activeIndex);
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
    _scheduleTableTabSync(_activeIndex);
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
    _scheduleTableTabSync(_activeIndex);
  }

  // ── Table-tab sync ─────────────────────────────────────────────────────────

  /// Debounced background sync for the tab at [index]. No-op when
  /// the tab is not a mesa or has no items yet (a brand-new mesa
  /// with zero lines doesn't need a ticket, and we'd only pollute
  /// the KDS with empties).
  ///
  /// When [flush] is true the debounce is skipped and the request
  /// fires immediately — used by "Enviar a mesa" so the QR is
  /// ready the instant the cashier opens the account sheet.
  void _scheduleTableTabSync(int index, {bool flush = false}) {
    final ctx = _contexts[index];
    final isTable = ctx.type == AccountType.mesa ||
        ctx.type == AccountType.mesaInmediata;
    if (!isTable) return;

    final label = ctx.tableLabel?.trim();
    if (label == null || label.isEmpty) return;

    _syncTimers[index]?.cancel();
    if (flush) {
      unawaited(_performTableTabSync(index));
      return;
    }
    _syncTimers[index] = Timer(_syncDebounce, () {
      unawaited(_performTableTabSync(index));
    });
  }

  /// Public entry point for the POS screen's "Enviar a mesa"
  /// action. Returns the `session_token` the backend settled on
  /// (may already be known locally), or null if the sync failed.
  Future<String?> flushTableTab({int? index}) async {
    final i = index ?? _activeIndex;
    _syncTimers[i]?.cancel();
    return _performTableTabSync(i);
  }

  Future<String?> _performTableTabSync(int index) async {
    if (index < 0 || index >= _cartCount) return null;
    final ctx = _contexts[index];
    final isTable = ctx.type == AccountType.mesa ||
        ctx.type == AccountType.mesaInmediata;
    if (!isTable) return null;
    final label = ctx.tableLabel?.trim();
    if (label == null || label.isEmpty) return null;
    final cart = _carts[index];
    if (cart.isEmpty) return null;

    final items = cart.map((line) {
      return {
        'product_uuid': line.product.uuid,
        'product_name': line.isService && line.customDescription != null
            ? line.customDescription!
            : line.product.name,
        'quantity': line.quantity,
        'unit_price': line.isService && line.customUnitPrice != null
            ? line.customUnitPrice
            : line.product.price,
      };
    }).toList();

    try {
      final api = apiOverride ?? ApiService(AuthService());
      final data = await api.upsertTableTab(
        label: label,
        items: items,
        customerName: ctx.customerName,
      );
      final token = data['session_token'] as String?;
      final orderId = data['order_id'] as String?;
      if (token == null || token.isEmpty) {
        developer.log(
          '[TABLE_TAB] upsert ok but no session_token in response',
          name: 'CartController',
        );
        return null;
      }
      // Only notify if something actually changed — avoids
      // spurious rebuilds while the cashier is scrolling.
      final before = _contexts[index];
      if (before.sessionToken != token || before.orderId != orderId) {
        _contexts[index] = before.copyWith(
          sessionToken: token,
          orderId: orderId,
        );
        notifyListeners();
        _persistContexts();
      }
      return token;
    } on AppError catch (e) {
      developer.log(
        '[TABLE_TAB] upsert failed: ${e.type} ${e.message}',
        name: 'CartController',
      );
      return null;
    } catch (e, st) {
      developer.log(
        '[TABLE_TAB] upsert unexpected error: $e',
        name: 'CartController',
        error: e,
        stackTrace: st,
      );
      return null;
    }
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
