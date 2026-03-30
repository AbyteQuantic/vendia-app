import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../models/product.dart';
import '../../models/cart_item.dart';

class CartController extends ChangeNotifier {
  static const int _cartCount = 10;
  static const String _storageKey = 'vendia_carts';

  final List<List<CartItem>> _carts = List.generate(_cartCount, (_) => []);

  int _activeIndex = 0;
  String _search = '';
  List<Product> _products = [];
  bool _productsLoaded = false;

  CartController() {
    _restoreCarts();
    _loadProducts();
  }

  static final List<Product> mockProducts = [
    const Product(
        id: 1,
        name: 'Gaseosa Cola 350ml',
        price: 2500,
        stock: 50,
        requiresContainer: true,
        containerPrice: 500),
    const Product(id: 2, name: 'Agua Cristal 500ml', price: 1800, stock: 80),
    const Product(id: 3, name: 'Papas Margarita 80g', price: 3200, stock: 30),
    const Product(id: 4, name: 'Arroz Diana 500g', price: 2900, stock: 100),
    const Product(id: 5, name: 'Aceite Girasol 250ml', price: 6500, stock: 20),
  ];

  Future<void> _loadProducts() async {
    try {
      final db = DatabaseService.instance;
      final local = await db.getAllProducts();
      _products = local.map(_localToProduct).toList();
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
      );

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
        final json = prefs.getString('${_storageKey}_$i');
        if (json != null && json.isNotEmpty) {
          _carts[i] = CartItem.decodeList(json);
        }
      }
      notifyListeners();
    } catch (_) {
      // Silently fail on restore — start with empty carts
    }
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
        activeCart.where((item) => item.product.id == product.id).firstOrNull;
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

  void clearActiveCart() {
    activeCart.clear();
    notifyListeners();
    _persistCarts();
  }

  void setSearch(String query) {
    _search = query;
    notifyListeners();
  }
}
