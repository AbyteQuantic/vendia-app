// Spec: specs/029-precios-multi-tier/spec.md
// Spec: specs/030-administracion-clientes-no-tienda/spec.md
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../models/customer.dart';
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

  /// Server-side credit_id of a fiado handshake that's still
  /// awaiting customer acceptance ("Seguir vendiendo" path). While
  /// this is non-null the slot is "locked": the cashier cannot
  /// silently discard the cart via [CartController.clearActiveCart]
  /// or [CartController.clearCartKeepContext], and the header chip
  /// renders an orange "Esperando…" badge so the cashier won't
  /// accidentally `switchCart` and forget the order is in-flight.
  ///
  /// Released by either:
  ///   1. The polling sweep — the credit moved off `status=pending`
  ///      server-side (accepted or rejected by the customer), or
  ///   2. The cashier explicitly invoking
  ///      [CartController.clearActiveCart]/[CartController.cancelPendingCredit]
  ///      with `force: true` — i.e. they pressed "Cancelar fiado".
  ///
  /// The field is persisted via [_persistContexts] so a process
  /// restart cannot "amnesia" the lock.
  final String? pendingCreditAccountId;

  const AccountContext({
    this.type = AccountType.mostrador,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
    this.sessionToken,
    this.orderId,
    this.pendingCreditAccountId,
  });

  AccountContext copyWith({
    AccountType? type,
    String? tableLabel,
    String? customerName,
    String? customerPhone,
    String? sessionToken,
    String? orderId,
    String? pendingCreditAccountId,
  }) {
    return AccountContext(
      type: type ?? this.type,
      tableLabel: tableLabel ?? this.tableLabel,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      sessionToken: sessionToken ?? this.sessionToken,
      orderId: orderId ?? this.orderId,
      pendingCreditAccountId:
          pendingCreditAccountId ?? this.pendingCreditAccountId,
    );
  }

  /// Returns a new context with [pendingCreditAccountId] reset to
  /// null. `copyWith` cannot express "explicitly null" because every
  /// optional parameter falls back to `this.field` — use this when
  /// the slot is being released after server acceptance/cancel.
  AccountContext clearPendingCredit() {
    return AccountContext(
      type: type,
      tableLabel: tableLabel,
      customerName: customerName,
      customerPhone: customerPhone,
      sessionToken: sessionToken,
      orderId: orderId,
      // pendingCreditAccountId intentionally omitted → null
    );
  }

  /// True when the cart on this slot is locked behind a fiado
  /// handshake awaiting customer acceptance. Surfaces cleanly to the
  /// UI without leaking the `pendingCreditAccountId` field — read
  /// sites should prefer this getter so adding richer states later
  /// (e.g. "rejected") stays internal to the controller.
  bool get hasPendingCredit =>
      pendingCreditAccountId != null && pendingCreditAccountId!.isNotEmpty;

  String get tabLabel {
    switch (type) {
      case AccountType.mesa:
        return tableLabel ?? 'Mesa';
      case AccountType.mesaInmediata:
        return tableLabel ?? 'Mesa';
      case AccountType.fiado:
        return customerName ?? 'Fiado';
      case AccountType.mostrador:
        return hasPendingCredit ? (customerName ?? 'Fiado') : '';
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'tableLabel': tableLabel,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'sessionToken': sessionToken,
        'orderId': orderId,
        'pendingCreditAccountId': pendingCreditAccountId,
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
      // Defensive default null: older serialised payloads from
      // pre-fiado-lock builds won't carry the field.
      pendingCreditAccountId: json['pendingCreditAccountId'] as String?,
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

  // F029 — tier de precios seleccionado para la venta entera. Default
  // 'retail' (cliente final / precio default) → comportamiento legacy
  // idéntico cuando la capacidad está OFF. Los valores válidos son los
  // 4 reconocidos por el backend: 'retail' | 'tier_1' | 'tier_2' | 'tier_3'.
  static const _validTiers = {'retail', 'tier_1', 'tier_2', 'tier_3'};
  String _selectedPriceTier = 'retail';

  /// Tier actualmente seleccionado para el cálculo de totales y para
  /// el `price_tier` que se enviará con la venta.
  String get selectedPriceTier => _selectedPriceTier;

  /// Cambia el tier activo y notifica para que el checkout recalcule el
  /// total. Valores no reconocidos se ignoran (defensive — el selector
  /// solo expone los 4 tiers válidos, pero protegemos contra payloads
  /// futuros).
  void setPriceTier(String tier) {
    if (!_validTiers.contains(tier)) return;
    if (_selectedPriceTier == tier) return;
    _selectedPriceTier = tier;
    notifyListeners();
  }

  /// F029: precio efectivo (con fallback retail) para [item] en el
  /// [tier] indicado. Para líneas de servicio respeta el customUnitPrice
  /// como hoy — el tier nunca aplica a servicios ad-hoc.
  double priceForItem(CartItem item, {String? tier}) {
    final effectiveTier = tier ?? _selectedPriceTier;
    if (item.isService) {
      return item.customUnitPrice ?? item.product.price;
    }
    return item.product.priceForTier(effectiveTier);
  }

  /// F029: subtotal por item para el tier activo (price × quantity).
  /// Para servicios ad-hoc respeta el customUnitPrice.
  double subtotalForItem(CartItem item, {String? tier}) =>
      priceForItem(item, tier: tier) * item.quantity;

  /// F029: true cuando [item] usa fallback retail porque su producto no
  /// tiene precio configurado para el tier activo. Las líneas de
  /// servicio (sin tiers por definición) NUNCA muestran el aviso.
  bool itemUsingRetailFallback(CartItem item, {String? tier}) {
    final effectiveTier = tier ?? _selectedPriceTier;
    if (effectiveTier == 'retail') return false;
    if (item.isService) return false;
    return !item.product.hasPriceForTier(effectiveTier);
  }

  // ── F030 — Cliente asociado a la venta ───────────────────────────
  //
  // Cliente identificado para la venta en curso. Null = venta anónima
  // (comportamiento legacy idéntico cuando la capacidad
  // `enable_customer_management` está OFF). Lo elige el cajero en el
  // tile "Cliente" del checkout; al confirmar la venta el `customer_id`
  // viaja en el payload de createSale.
  Customer? _selectedCustomer;

  /// Cliente actualmente asociado a la venta, o null si es anónima.
  Customer? get selectedCustomer => _selectedCustomer;

  /// UUID del cliente listo para el payload `customer_id` de createSale.
  /// Null cuando no hay cliente o su id está vacío (defensive — un
  /// cliente sin uuid no debe contaminar el payload).
  String? get salePayloadCustomerId {
    final c = _selectedCustomer;
    if (c == null || c.id.isEmpty) return null;
    return c.id;
  }

  /// Asocia (o desasocia, con null) un [customer] a la venta en curso.
  /// Notifica solo cuando el cliente cambia de verdad — el checkout se
  /// suscribe vía Provider y repintar de más es desperdicio.
  void setCustomer(Customer? customer) {
    final current = _selectedCustomer;
    if (current?.id == customer?.id) return;
    _selectedCustomer = customer;
    notifyListeners();
  }

  // ── Background table-tab persistence ───────────────────────────
  //
  // Per-tab sync timers (now unused, kept for cleanup in dispose)
  final Map<int, Timer> _syncTimers = {};

  // Per-tab hydration flag. The POS listens on this to decide
  // whether to show a skeleton over the cart while we fetch the
  // server-side open tab on mesa selection. We track by tab
  // index (not label) because the cashier can swap tabs mid-
  // fetch; anchoring on the tab is what the UI cares about.
  final Set<int> _hydratingTabs = {};
  // Tracks which cart indexes have been hydrated from the server
  // during this sync cycle, so we don't re-fetch on every debounce.
  final Set<int> _hydratedOnce = {};

  bool isHydratingTab(int index) => _hydratingTabs.contains(index);

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
        // sellableOnly: el POS no vende platos de menú incompletos (sin receta
        // con ingredientes). Mantiene la caché Isar limpia para que tampoco
        // aparezcan offline. Spec 078.
        final res =
            await api.fetchProducts(page: 1, perPage: 100, sellableOnly: true);
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

  /// Returns the tab index that already holds [label], or -1.
  int _tabIndexForMesa(String label) {
    for (int i = 0; i < _cartCount; i++) {
      final c = _contexts[i];
      if ((c.type == AccountType.mesa || c.type == AccountType.mesaInmediata) &&
          c.tableLabel == label) {
        return i;
      }
    }
    return -1;
  }

  void setContext(AccountContext ctx) {
    // ── Duplicate-mesa guard ──
    // If the label is already on another tab, auto-switch there
    // instead of creating a duplicate.
    final isMesa = ctx.type == AccountType.mesa ||
        ctx.type == AccountType.mesaInmediata;
    final label = (ctx.tableLabel ?? '').trim();
    if (isMesa && label.isNotEmpty) {
      final existing = _tabIndexForMesa(label);
      if (existing != -1 && existing != _activeIndex) {
        // Switch to the tab that already owns this mesa
        _activeIndex = existing;
        notifyListeners();
        return;
      }
    }

    final previous = _contexts[_activeIndex];
    _contexts[_activeIndex] = ctx;
    _hydratedOnce.remove(_activeIndex);
    notifyListeners();
    _persistContexts();

    final switchedToNewMesa = isMesa &&
        label.isNotEmpty &&
        (previous.type != ctx.type ||
            (previous.tableLabel ?? '') != label);

    if (switchedToNewMesa) {
      unawaited(_hydrateActiveTab());
    }
  }

  void clearContextForActive() {
    _contexts[_activeIndex] = const AccountContext();
    notifyListeners();
    _persistContexts();
  }

  /// Reset every cart slot whose context refers to [label] back to
  /// mostrador. Used when a tab auto-closes — the mesa bubble in the
  /// POS header should turn white the moment the cuenta is paid.
  void clearContextForLabel(String label) {
    var changed = false;
    for (var i = 0; i < _cartCount; i++) {
      final ctx = _contexts[i];
      final isMesa = ctx.type == AccountType.mesa ||
          ctx.type == AccountType.mesaInmediata;
      if (isMesa && (ctx.tableLabel ?? '').trim() == label.trim()) {
        _contexts[i] = const AccountContext();
        _carts[i].clear();
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _persistContexts();
      _persistCarts();
    }
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  int get activeIndex => _activeIndex;

  List<CartItem> get activeCart => _carts[_activeIndex];

  List<CartItem> cart(int index) => _carts[index];

  /// Total del carrito activo. F029: itera respetando el tier elegido
  /// (con fallback retail por item cuando el tier no está configurado).
  /// Cuando `selectedPriceTier == 'retail'` el resultado es idéntico al
  /// previo a F029 — invariante de retrocompatibilidad (AC-07).
  double get activeTotal {
    if (_selectedPriceTier == 'retail') {
      // Camino caliente que no toca product.priceForTier — un test de
      // performance regresivo evitaría regressions futuras.
      return activeCart.fold(0.0, (sum, item) => sum + item.subtotal);
    }
    return activeCart.fold(
      0.0,
      (sum, item) => sum + subtotalForItem(item),
    );
  }

  /// F029: total para un tier arbitrario sin cambiar el estado actual.
  /// Útil para tests y para previews futuros ("¿cuánto costaría a
  /// mayorista?") sin disparar notifyListeners.
  double totalForTier(String tier) {
    if (!_validTiers.contains(tier)) return activeTotal;
    if (tier == 'retail') {
      return activeCart.fold(0.0, (sum, item) => sum + item.subtotal);
    }
    return activeCart.fold(
      0.0,
      (sum, item) => sum + subtotalForItem(item, tier: tier),
    );
  }

  String get formattedTotal => _formatCop(activeTotal.round());

  /// Subtotal por item formateado para el TIER ACTIVO. El carrito debe
  /// mostrar el MISMO precio que se cobra: antes usaba
  /// `CartItem.formattedSubtotal` (siempre retail), así que con un tier
  /// activo las líneas no sumaban al total del checkout y el cajero veía
  /// dos números distintos para lo mismo.
  String formattedSubtotalForItem(CartItem item) =>
      _formatCop(subtotalForItem(item).round());

  static String _formatCop(int cents) {
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

  /// Returns true if added, false if blocked (e.g. price is 0).
  /// Does NOT auto-sync to the server. The cashier must press
  /// "ENVIAR PEDIDO" (which calls flushTableTab) to send items.
  bool addProduct(Product product) {
    if (product.price <= 0) return false;
    final existing =
        activeCart.where((item) => item.product.uuid == product.uuid).firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      activeCart.add(CartItem(product: product));
    }
    notifyListeners();
    _persistCarts();
    return true;
  }

  void increment(Product product) {
    final item =
        activeCart.where((i) => i.product.uuid == product.uuid).firstOrNull;
    if (item == null) return;
    item.quantity++;
    notifyListeners();
    _persistCarts();
  }

  void decrement(Product product) {
    final index = activeCart.indexWhere((i) => i.product.uuid == product.uuid);
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

  // ── Table-tab sync ─────────────────────────────────────────────────────────


  /// Re-fetch products from the server so stock updates are visible.
  Future<void> refreshProducts() => _loadProducts();

  /// Called after successfully removing an item from a server-side tab.
  /// Restores local ISAR stock and refreshes the product grid.
  Future<void> onTabItemRemoved(String productUuid, int quantity) async {
    if (productUuid.isEmpty || quantity <= 0) return;
    try {
      await DatabaseService.instance.adjustStock(productUuid, quantity);
    } catch (_) {
      // ISAR not initialized (tests) or disk error — continue gracefully
    }
    try {
      await DatabaseService.instance.releaseReservation({
        productUuid: quantity,
      });
    } on StateError catch (_) {
      // ISAR not initialized in tests — fine
    }
    final idx = _products.indexWhere((p) => p.uuid == productUuid);
    if (idx != -1) {
      final old = _products[idx];
      _products[idx] = Product(
        id: old.id,
        uuid: old.uuid,
        name: old.name,
        price: old.price,
        stock: (old.stock + quantity).clamp(0, 999999),
        imageUrl: old.imageUrl,
        isAvailable: old.isAvailable,
        requiresContainer: old.requiresContainer,
        containerPrice: old.containerPrice,
        barcode: old.barcode,
        presentation: old.presentation,
        content: old.content,
      );
    }
    notifyListeners();
  }


  /// Public entry point for tests and force-refresh flows.
  /// Fires the server lookup for the currently active tab; no-op
  /// when the active context isn't a mesa. Safe to call multiple
  /// times — guarded by [_hydratingTabs] to avoid concurrent
  /// fetches on the same index.
  Future<void> hydrateActiveTab() => _hydrateActiveTab();

  Future<void> _hydrateActiveTab() async {
    final index = _activeIndex;
    final ctx = _contexts[index];
    final isTable = ctx.type == AccountType.mesa ||
        ctx.type == AccountType.mesaInmediata;
    if (!isTable) return;
    final label = ctx.tableLabel?.trim();
    if (label == null || label.isEmpty) return;
    if (_hydratingTabs.contains(index)) return;

    _hydratingTabs.add(index);
    notifyListeners();

    // Snapshot the cart BEFORE we go to the network. If the
    // cashier adds a product while we're fetching, we detect it
    // via length + first-uuid and skip the overwrite — the
    // debounced sync will push the merged state up instead.
    final cartBefore = _carts[index]
        .map((line) => '${line.product.uuid}:${line.quantity}')
        .join('|');

    try {
      final api = apiOverride ?? ApiService(AuthService());
      final tab = await api
          .fetchTableTabByLabel(label)
          .timeout(const Duration(seconds: 10));
      if (tab == null) {
        // No open ticket server-side — nothing to hydrate.
        // Leave the local cart as-is (could be empty, could be
        // the cashier's fresh order about to be sent).
        return;
      }

      // Bail out if the cashier already moved on (switched tab,
      // changed mesa) or touched the cart while we were fetching.
      final still = _activeIndex == index &&
          _contexts[index].type == ctx.type &&
          (_contexts[index].tableLabel ?? '') == (ctx.tableLabel ?? '');
      final cartNow = _carts[index]
          .map((line) => '${line.product.uuid}:${line.quantity}')
          .join('|');
      if (!still) return;
      if (cartNow != cartBefore) {
        // Keep the server token metadata so the QR works, but
        // don't clobber local edits.
        final token = tab['session_token'] as String?;
        final orderId = tab['order_id'] as String?;
        if (token != null || orderId != null) {
          _contexts[index] = _contexts[index].copyWith(
            sessionToken: token,
            orderId: orderId,
          );
          notifyListeners();
          _persistContexts();
        }
        return;
      }

      // Safe to hydrate: replace local cart with server items.
      final rawItems = (tab['items'] as List?) ?? const [];
      final rebuilt = <CartItem>[];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final productUuid = (m['product_uuid'] as String?) ?? '';
        final productName = (m['product_name'] as String?) ?? 'Producto';
        final qty = (m['quantity'] as num?)?.toInt() ?? 1;
        final unit = (m['unit_price'] as num?)?.toDouble() ?? 0;
        if (productUuid.isEmpty || qty < 1) continue;
        // Prefer the real catalog Product (keeps image, barcode,
        // etc. for the cart UI). Fall back to a synthetic Product
        // carrying just what we need — the cart widgets key on
        // product.uuid so "+"/"−" still match.
        final catalog = _products
            .where((p) => p.uuid == productUuid)
            .firstOrNull;
        final product = catalog ??
            Product(
              id: 0,
              uuid: productUuid,
              name: productName,
              price: unit,
              stock: 9999,
            );
        rebuilt.add(CartItem(product: product, quantity: qty));
      }

      _carts[index]
        ..clear()
        ..addAll(rebuilt);
      _contexts[index] = _contexts[index].copyWith(
        sessionToken: tab['session_token'] as String?,
        orderId: tab['order_id'] as String?,
      );
      notifyListeners();
      _persistCarts();
      _persistContexts();
    } on AppError catch (e) {
      developer.log(
        '[TABLE_TAB] hydrate failed: ${e.type} ${e.message}',
        name: 'CartController',
      );
    } catch (e, st) {
      developer.log(
        '[TABLE_TAB] hydrate unexpected error: $e',
        name: 'CartController',
        error: e,
        stackTrace: st,
      );
    } finally {
      _hydratingTabs.remove(index);
      if (hasListeners) notifyListeners();
    }
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

    // Build the lines payload once; reused by API push and ISAR commit.
    final lines = <({String productUuid, String productName, int quantity, double unitPrice})>[];
    for (final line in cart) {
      lines.add((
        productUuid: line.product.uuid,
        productName: line.isService && line.customDescription != null
            ? line.customDescription!
            : line.product.name,
        quantity: line.quantity,
        unitPrice: line.isService && line.customUnitPrice != null
            ? line.customUnitPrice!
            : line.product.price,
      ));
    }

    try {
      // Step 1: Push to backend FIRST. If this fails the cart stays
      // intact and ISAR is untouched, so the cashier can retry safely.
      final api = apiOverride ?? ApiService(AuthService());
      final itemMap = <String, Map<String, dynamic>>{};
      for (final line in cart) {
        final uuid = line.product.uuid;
        if (itemMap.containsKey(uuid)) {
          itemMap[uuid]!['quantity'] =
              (itemMap[uuid]!['quantity'] as int) + line.quantity;
        } else {
          itemMap[uuid] = {
            'product_uuid': uuid,
            'product_name': line.isService && line.customDescription != null
                ? line.customDescription!
                : line.product.name,
            'quantity': line.quantity,
            'unit_price': line.isService && line.customUnitPrice != null
                ? line.customUnitPrice
                : line.product.price,
          };
        }
      }
      final items = itemMap.values.toList();

      final data = await api.addItemsToTableTab(
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

      // Step 2: Backend confirmed → atomic ISAR commit (reserve stock +
      // append items + recompute totals). This is the SSOT write that
      // streams broadcast to header, POS cards, and TabReviewScreen.
      // Only StateError ("DatabaseService not initialized") is tolerated
      // so widget tests without an initialized Isar still exercise the
      // API/context path. Real Isar exceptions MUST propagate so the
      // outer catch logs them and the cashier sees the error snackbar
      // instead of a phantom "all good" with stale stock.
      try {
        await DatabaseService.instance
            .commitOrderToTab(label: label, lines: lines);
        await DatabaseService.instance.applyServerTabSnapshot({
          'label': label,
          'session_token': token,
          'order_id': orderId,
        });
      } on StateError catch (e) {
        developer.log(
          '[TABLE_TAB] ISAR not initialized (test env): $e',
          name: 'CartController',
        );
      }

      // Step 3: Update context with server tokens.
      final before = _contexts[index];
      if (before.sessionToken != token || before.orderId != orderId) {
        _contexts[index] = before.copyWith(
          sessionToken: token,
          orderId: orderId,
        );
        notifyListeners();
        _persistContexts();
      }

      // Step 4: Clear local cart — items now live in LocalTableTab.
      _carts[index].clear();
      notifyListeners();
      _persistCarts();
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

  /// Clear the active slot — empties the cart AND drops the context
  /// back to mostrador.
  ///
  /// When the slot is locked behind a pending fiado handshake
  /// (`pendingCreditAccountId != null`) this is a **no-op unless
  /// `force: true`**. The cashier loses real money when an in-flight
  /// fiado evaporates because they tapped C2 by accident — so the
  /// destruction has to be deliberate. Returns `true` if the slot was
  /// cleared, `false` if it was preserved.
  bool clearActiveCart({bool force = false}) {
    final ctx = _contexts[_activeIndex];
    if (ctx.hasPendingCredit && !force) {
      developer.log(
        '[CART] clearActiveCart suppressed: slot $_activeIndex has pending '
        'credit ${ctx.pendingCreditAccountId}',
        name: 'CartController',
      );
      return false;
    }
    activeCart.clear();
    _contexts[_activeIndex] = const AccountContext();
    // F030: una venta cerrada/limpiada arranca anónima de nuevo — el
    // cliente no debe "pegarse" a la siguiente venta sin que el cajero
    // lo vuelva a elegir.
    _selectedCustomer = null;
    notifyListeners();
    _persistCarts();
    _persistContexts();
    return true;
  }

  /// Clear cart items but KEEP the account context (mesa stays assigned).
  ///
  /// Same `pendingCreditAccountId` guard as [clearActiveCart] — an
  /// implicit cart wipe (e.g. after `_sendOrder`) MUST NOT erase the
  /// fiado items the cashier already promised the customer. Pass
  /// `force: true` only from the explicit cancel-fiado flow.
  bool clearCartKeepContext({bool force = false}) {
    final ctx = _contexts[_activeIndex];
    if (ctx.hasPendingCredit && !force) {
      developer.log(
        '[CART] clearCartKeepContext suppressed: slot $_activeIndex has '
        'pending credit ${ctx.pendingCreditAccountId}',
        name: 'CartController',
      );
      return false;
    }
    activeCart.clear();
    notifyListeners();
    _persistCarts();
    return true;
  }

  // ── Pending credit (fiado handshake) lock ────────────────────────────────
  //
  // The cashier presses "Seguir vendiendo" on the FiadoWaitingRoom and
  // returns to POS while the customer hasn't accepted yet. We mark the
  // slot as locked so an accidental switchCart + clearActiveCart can't
  // erase the in-flight order.

  /// Snapshot of every `pendingCreditAccountId` currently parked across
  /// the 10 slots. Used by the POS polling loop to reconcile against
  /// `/api/v1/credits?status=pending` — anything missing from that list
  /// has been accepted (or cancelled) server-side and gets released.
  Set<String> get pendingCreditAccountIds {
    final ids = <String>{};
    for (final ctx in _contexts) {
      if (ctx.hasPendingCredit) ids.add(ctx.pendingCreditAccountId!);
    }
    return ids;
  }

  /// Returns the slot index parking [creditAccountId], or -1 when
  /// no slot tracks it.
  int slotForPendingCredit(String creditAccountId) {
    if (creditAccountId.isEmpty) return -1;
    for (var i = 0; i < _cartCount; i++) {
      if (_contexts[i].pendingCreditAccountId == creditAccountId) return i;
    }
    return -1;
  }

  /// Mark the active slot as locked behind a pending fiado handshake.
  /// Call this when [_FiadoWaitingRoom] returns with
  /// `acceptedByCustomer == false` — the credit_account stays in
  /// `status=pending` server-side and the slot must persist its cart
  /// + customer info until the customer signs.
  void setPendingCreditOnActive({
    required String creditAccountId,
    String? customerName,
    String? customerPhone,
  }) {
    if (creditAccountId.isEmpty) return;
    final before = _contexts[_activeIndex];
    _contexts[_activeIndex] = before.copyWith(
      // Don't widen the AccountType to fiado here — pendingCreditAccountId
      // is the load-bearing flag, and switching type would reshape the
      // header chip color in ways the cashier didn't ask for. The
      // hasPendingCredit getter on every type-branch is what gates the UI.
      customerName: customerName ?? before.customerName,
      customerPhone: customerPhone ?? before.customerPhone,
      pendingCreditAccountId: creditAccountId,
    );
    notifyListeners();
    _persistContexts();
  }

  /// Explicit cashier-initiated cancel of a pending fiado on the
  /// active slot. Wipes the cart, the context, and persists. Returns
  /// the credit_id that was released so the caller can fire the
  /// matching server-side cancel call. Returns null when the slot
  /// has no pending credit (defensive — UI should not have offered
  /// the action in that case).
  String? cancelPendingCreditOnActive() {
    final ctx = _contexts[_activeIndex];
    final id = ctx.pendingCreditAccountId;
    if (id == null || id.isEmpty) return null;
    activeCart.clear();
    _contexts[_activeIndex] = const AccountContext();
    notifyListeners();
    _persistCarts();
    _persistContexts();
    return id;
  }

  /// Release every slot whose pendingCreditAccountId is in
  /// [acceptedOrRejectedIds]. Called by the POS polling tick when the
  /// server confirms the customer accepted (or rejected) the
  /// handshake — the cashier no longer needs the slot held open.
  ///
  /// We clear the slot wholesale (cart + context) because the items
  /// were already persisted on the server-side `Sale` row at handshake
  /// time. Returns the list of slot indexes that were released so the
  /// caller can fire any UX side-effects (toast, switchCart, …).
  List<int> releasePendingCredits(Iterable<String> acceptedOrRejectedIds) {
    final released = <int>[];
    final idSet = acceptedOrRejectedIds.toSet();
    for (var i = 0; i < _cartCount; i++) {
      final ctx = _contexts[i];
      final id = ctx.pendingCreditAccountId;
      if (id == null || id.isEmpty) continue;
      if (!idSet.contains(id)) continue;
      _carts[i].clear();
      _contexts[i] = const AccountContext();
      released.add(i);
    }
    if (released.isNotEmpty) {
      notifyListeners();
      _persistCarts();
      _persistContexts();
    }
    return released;
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
