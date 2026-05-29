import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_sale.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/branch_provider.dart';
import '../../services/role_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/online_orders_bell.dart';
import '../../widgets/profile_photo_avatar.dart';
import '../../widgets/profile_photo_picker.dart';
import '../../widgets/push_optin_card.dart';
import '../settings/notifications_settings_screen.dart';
import '../../widgets/trial_bar.dart';
import '../auth/login_screen.dart';
import '../inventory/add_merchandise_screen.dart';
import '../inventory/reorder_screen.dart';
import '../pos/pos_screen.dart';
import '../../database/sync/sales_sync.dart';
import '../../widgets/sync_status_banner.dart';
import '../../widgets/capabilities_reel.dart';
import '../../widgets/dashboard_module_grid.dart';
import '../../config/dashboard_modules.dart';
import '../../utils/credit_labels.dart';
import 'business_profile_screen.dart';
import 'financial_dashboard_screen.dart';
import 'product_insights_screen.dart';

// ── Dashboard Data (computed from Isar) ─────────────────────────────────────

class _DashboardData {
  final double totalToday;
  final int txCount;
  final String topProduct;
  final int prodCount;
  /// Recent sales — either from API (Map) or local Isar (LocalSale).
  /// The tile builder handles both types.
  final List<dynamic> recentSales;

  const _DashboardData({
    required this.totalToday,
    required this.txCount,
    required this.topProduct,
    required this.prodCount,
    required this.recentSales,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════

class DashboardScreen extends StatefulWidget {
  final String ownerName;
  final String businessName;

  const DashboardScreen({
    super.key,
    required this.ownerName,
    required this.businessName,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseService.instance;

  // Isar lazy streams — fire a void event on every collection change
  late final StreamSubscription _salesSub;
  late final StreamSubscription _productsSub;
  Timer? _loadDebounce;

  // Reactive data holder
  _DashboardData _data = const _DashboardData(
    totalToday: 0, txCount: 0, topProduct: '—', prodCount: 0, recentSales: [],
  );

  // Low-stock alert count for the reorder suggestion badge.
  int _lowStockCount = 0;

  // Storefront open/closed flag. The catálogo público reacts to this
  // value (add-to-cart disabled when closed) so it must be obvious
  // on the dashboard header and fast to flip. Loaded from the backend
  // on mount; failures keep the default `false`.
  bool _isStoreOpen = false;
  bool _loadingStoreStatus = false;

  // F036: Dashboard adaptativo. El grid de módulos se construye a
  // partir del registro declarativo (dashboard_modules.dart) filtrado
  // por el tipo de negocio + los feature flags del tenant. Se cargan
  // en initState desde AuthService (offline-safe). Mientras no carguen,
  // el grid se construye con defaults (solo core visible).
  String? _businessType;
  // Lista completa de tipos seleccionados — un tenant puede declarar
  // múltiples categorías (ej. tienda_barrio + restaurante). El header
  // las muestra como chip(s) clickeable(s).
  List<String> _businessTypes = const [];
  FeatureFlags _featureFlags = const FeatureFlags();

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncFromServer();
    _loadLowStockCount();
    _loadStoreStatus();
    _loadCapabilityFlags();

    _salesSub = _db.watchSalesLazy().listen((_) => _debouncedLoad());

    _productsSub = _db.watchProductsLazy().listen((_) => _debouncedLoad());

    // Reload all dashboard data when the branch changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bp = context.read<BranchProvider>();
      _prevBranchId = bp.currentBranchId;
      bp.addListener(_onBranchChanged);
    });
  }

  String? _prevBranchId;

  void _onBranchChanged() {
    if (!mounted) return;
    final newId = context.read<BranchProvider>().currentBranchId;
    if (newId != _prevBranchId) {
      _prevBranchId = newId;
      // Small delay to let ApiService.currentBranchId sync
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        _loadData();
        _syncFromServer();
        _loadLowStockCount();
        _loadStoreStatus();
      });
    }
  }

  /// Pull sales + products from the server so the dashboard is up to date
  /// even after a fresh login or tenant switch that cleared Isar.
  Future<void> _syncFromServer() async {
    // Run both syncs in parallel for speed
    await Future.wait([
      SalesSyncService.fullSync().catchError((_) {}),
      _syncProducts(),
    ]);
  }

  /// Fetch all tenant products from the API and upsert into Isar.
  /// This ensures every device (owner, cashier) sees the same catalog.
  Future<void> _syncProducts() async {
    try {
      final api = ApiService(AuthService());
      final res = await api.fetchProducts(perPage: 500);
      final items = ((res['data'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map((e) => LocalProduct.fromJson(e))
          .toList();
      if (items.isNotEmpty) {
        await _db.replaceAllProducts(items);
      }
    } catch (_) {
      // Offline — keep whatever is in Isar.
    }
  }

  Future<void> _loadStoreStatus() async {
    try {
      final api = ApiService(AuthService());
      final config = await api.fetchStoreConfig();
      if (mounted) {
        setState(() {
          _isStoreOpen = config['is_delivery_open'] == true;
        });
      }
    } catch (_) {
      // Offline / not configured — keep the default "closed" state.
    }
  }

  /// F036: carga el tipo de negocio + los feature flags persistidos
  /// por AuthService (offline-safe). Alimentan el grid adaptativo de
  /// módulos. Fail-closed: cualquier error deja el grid con solo los
  /// módulos core visibles.
  Future<void> _loadCapabilityFlags() async {
    try {
      final auth = AuthService();
      final flags = await auth.getFeatureFlags();
      final type = await auth.getBusinessType();
      final types = await auth.getBusinessTypes();
      if (mounted) {
        setState(() {
          _featureFlags = flags;
          _businessType = (type != null && type.isNotEmpty) ? type : null;
          _businessTypes = types;
        });
      }
    } catch (_) {
      // Offline / sin flags — el grid se queda con solo los core.
    }
  }

  /// Flip the storefront open/closed flag. Reads as "optimistic" from
  /// the user's POV — the Switch visual stays put until the PATCH
  /// returns OK, and the spinner on the pill covers the latency. On
  /// failure the local flag is not touched so the Switch visually
  /// reverts to the pre-tap value. SnackBar surfaces the error.
  Future<void> _toggleStoreStatus(bool val) async {
    HapticFeedback.mediumImpact();
    setState(() => _loadingStoreStatus = true);
    try {
      final api = ApiService(AuthService());
      await api.updateStoreStatus(val);
      if (mounted) setState(() => _isStoreOpen = val);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar estado: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingStoreStatus = false);
    }
  }

  Future<void> _loadLowStockCount() async {
    try {
      final api = ApiService(AuthService());
      final alerts = await api.fetchInventoryAlerts();
      if (mounted) setState(() => _lowStockCount = alerts.length);
    } catch (_) {
      // Offline — keep at 0
    }
  }

  @override
  @override
  void dispose() {
    _loadDebounce?.cancel();
    _salesSub.cancel();
    _productsSub.cancel();
    try {
      context.read<BranchProvider>().removeListener(_onBranchChanged);
    } catch (_) {}
    super.dispose();
  }

  /// Debounce Isar change events so rapid writes during sync don't
  /// trigger N concurrent _loadData reads.
  void _debouncedLoad() {
    _loadDebounce?.cancel();
    _loadDebounce = Timer(const Duration(milliseconds: 300), _loadData);
  }

  Future<void> _loadData() async {
    int prodCount = 0;
    double totalToday = 0;
    int txCount = 0;
    String top = '—';
    List<dynamic> recentSales = [];

    try {
      final api = ApiService(AuthService());

      // Parallel: KPIs + recent sales (both branch-scoped)
      final results = await Future.wait([
        api.fetchAnalyticsDashboard(),
        api.fetchSalesHistoryByPeriod(period: 'today', page: 1, perPage: 10),
      ]);

      final analytics = results[0] as Map<String, dynamic>;
      prodCount = (analytics['product_count'] as num?)?.toInt() ?? 0;
      totalToday = (analytics['total_sales_today'] as num?)?.toDouble() ?? 0;
      txCount = (analytics['transaction_count'] as num?)?.toInt() ?? 0;

      final apiSales = results[1] as List<dynamic>;
      recentSales = apiSales;

      // Top product from API sales items
      if (apiSales.isNotEmpty) {
        final counts = <String, int>{};
        for (final s in apiSales) {
          if (s is! Map) continue;
          final items = (s['Items'] ?? s['items'] ?? []) as List;
          for (final it in items) {
            if (it is! Map) continue;
            final name = (it['name'] ?? it['product_name'] ?? '') as String;
            final qty = (it['quantity'] as num?)?.toInt() ?? 1;
            if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + qty;
          }
        }
        if (counts.isNotEmpty) {
          final sorted = counts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          top = sorted.first.key;
        }
      }
    } catch (_) {
      // Fallback to local Isar if offline
      final sales = await _db.getSalesToday();
      totalToday = sales.fold<double>(0, (sum, s) => sum + s.total);
      txCount = sales.length;
      final allProducts = await _db.getAllProducts();
      prodCount = allProducts.length;
      sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      top = _topProduct(sales);
      recentSales = sales.take(10).toList();
    }

    if (mounted) {
      setState(() {
        _data = _DashboardData(
          totalToday: totalToday,
          txCount: txCount,
          topProduct: top,
          prodCount: prodCount,
          recentSales: recentSales,
        );
      });
    }
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatCOP(int amount) {
    if (amount == 0) return '\$0';
    final s = amount.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  String _topProduct(List<LocalSale> sales) {
    if (sales.isEmpty) return '—';
    final counts = <String, int>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        if (item.isContainerCharge) continue;
        counts[item.productName] =
            (counts[item.productName] ?? 0) + item.quantity;
      }
    }
    if (counts.isEmpty) return '—';
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return 'Hace ${diff.inDays}d';
  }

  IconData _payIcon(String method) => switch (method) {
        'transfer' || 'nequi' || 'daviplata' => Icons.phone_android_rounded,
        'card' => Icons.credit_card_rounded,
        'credit' => Icons.menu_book_rounded,
        _ => Icons.payments_rounded,
      };

  String _payLabel(String method, BuildContext context) => switch (method) {
        'transfer' => 'Transferencia',
        'nequi' => 'Nequi',
        'daviplata' => 'Daviplata',
        'card' => 'Tarjeta',
        'credit' => CreditLabels.of(context).nounSingularCapitalized,
        _ => 'Efectivo',
      };

  /// Confirm + clear the session and bounce back to the login screen.
  /// Same logout that lived inside admin_hub, mirrored here so the
  /// cashier (who can't reach Configuración) isn't trapped.
  Future<void> _onLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cerrar sesión?',
            style: TextStyle(fontSize: 22)),
        content: const Text(
            'Sus datos locales se mantendrán guardados.',
            style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar sesión',
                style: TextStyle(fontSize: 18, color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(child: ScrollConfiguration(
        behavior:
            ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: RefreshIndicator.adaptive(
          color: Colors.white,
          onRefresh: _refresh,
          displacement: 40,
          edgeOffset: topPad + 76,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              // ── Sticky Gradient Header ──────────────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: _HeroHeaderDelegate(
                  topPadding: topPad,
                  ownerName: widget.ownerName,
                  businessName: widget.businessName,
                  businessTypes: _businessTypes,
                  branchName: context.watch<BranchProvider>().currentBranch?.name,
                  isStoreOpen: _isStoreOpen,
                  loadingStoreStatus: _loadingStoreStatus,
                  onToggleStore: _toggleStoreStatus,
                  onLogout: _onLogout,
                  onEditBusinessTypes: () async {
                    HapticFeedback.lightImpact();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BusinessProfileScreen()),
                    );
                    if (mounted) _loadCapabilityFlags();
                  },
                  todayLabel: _todayLabel(),
                ),
              ),

              // ── Spec 038 — Tarjeta de opt-in a push notifications ──
              // Solo se muestra si Firebase está disponible y el usuario
              // aún no tiene un dispositivo registrado activo. En cualquier
              // otro caso es 0px de alto (transparente al layout).
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: PushOptinGate(),
                ),
              ),

              // ── Glass Stats Cards ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Column(
                    children: [
                        if (context.watch<RoleManager>().canSeeFinances) ...[
                          _GlassCard(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) =>
                                      const FinancialDashboardScreen()));
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 52, height: 52,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.trending_up_rounded,
                                      color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Ventas de hoy',
                                          style: TextStyle(
                                              fontSize: 15,
                                              color: AppTheme.textSecondary,
                                              fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 2),
                                      Text(_formatCOP(_data.totalToday.round()),
                                          style: const TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.textPrimary,
                                              letterSpacing: -1)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _data.txCount > 0
                                        ? AppTheme.success.withValues(alpha: 0.12)
                                        : AppTheme.warning.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _data.txCount > 0
                                        ? '${_data.txCount} venta${_data.txCount > 1 ? "s" : ""}'
                                        : 'primer día',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _data.txCount > 0
                                            ? AppTheme.success
                                            : AppTheme.warning),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _GlassCard(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) =>
                                          const ProductInsightsScreen()));
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.star_rounded,
                                          color: Color(0xFFF59E0B), size: 22),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('Más vendido',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(_data.topProduct,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _GlassCard(
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AddMerchandiseScreen(),
                                    ),
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 40, height: 40,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.inventory_2_rounded,
                                              color: Color(0xFF6366F1), size: 22),
                                        ),
                                        const Spacer(),
                                        Icon(Icons.chevron_right_rounded,
                                            color: Colors.grey.shade400, size: 20),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('Inventario',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                        _data.prodCount == 0
                                            ? 'Vacío'
                                            : '${_data.prodCount} ref.',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Low Stock Alert ────────────────────────────────
                if (_lowStockCount > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ReorderScreen(),
                          ));
                          _loadLowStockCount();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.warning_amber_rounded,
                                    color: Color(0xFFD97706), size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_lowStockCount producto${_lowStockCount == 1 ? '' : 's'} con stock bajo',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF92400E)),
                                    ),
                                    const Text('Toca para ver pedidos sugeridos',
                                        style: TextStyle(fontSize: 13, color: Color(0xFFB45309))),
                                  ],
                                ),
                              ),
                              const Icon(Icons.shopping_cart_checkout_rounded,
                                  color: Color(0xFFD97706), size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── F037: Reel de capacidades ────────────────────────
                // Carousel horizontal con las capacidades opcionales
                // que el dueño aún NO activó. Se oculta cuando la
                // lista está vacía (AC-07). Tocar una card abre
                // `BusinessCapabilitiesScreen` con el toggle resaltado.
                SliverToBoxAdapter(
                  child: CapabilitiesReel(
                    key: const Key('dashboard_capabilities_reel'),
                    modules: unactivatedOptionalModules(_featureFlags),
                    onReturned: _loadCapabilityFlags,
                  ),
                ),

                // ── F036: Grid adaptativo de módulos ────────────────
                // Reemplaza el antiguo stack imperativo de tarjetas
                // (Reporte, Clientes, Cotizaciones, Promociones,
                // Proveedores, Insumos, Recetas, Órdenes, Trabajos).
                // Las 4 categorías se construyen filtrando el registro
                // `dashboardModules` por el tipo de negocio + flags.
                SliverToBoxAdapter(
                  child: DashboardModuleGrid(
                    businessType: _businessType,
                    flags: _featureFlags,
                  ),
                ),

                // ── Recent Sales Header ─────────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22, 20, 22, 4),
                    child: Text('Últimas ventas',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary)),
                  ),
                ),

                // ── Recent Sales List (REACTIVE) ────────────────────
                SliverToBoxAdapter(
                  child: _data.recentSales.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Center(
                            child: Text(
                              'Aún no hay ventas hoy.\n¡Registre la primera!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary),
                            ),
                          ),
                        )
                      : Container(
                          margin:
                              const EdgeInsets.fromLTRB(24, 12, 24, 24),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceGrey,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: ListView.separated(
                            physics:
                                const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: _data.recentSales.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: 76,
                              color: AppTheme.borderColor,
                            ),
                            itemBuilder: (_, i) =>
                                _buildSaleTile(_data.recentSales[i]),
                          ),
                        ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
        )),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            18, 12, 18, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            onPressed: () async {
              HapticFeedback.lightImpact();
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PosScreen(),
              ));
            },
            icon: const Icon(Icons.add_rounded, size: 26),
            label: const Text('Registrar nueva venta'),
          ),
        ),
      ),
    );
  }

  Widget _buildSaleTile(dynamic sale) {
    String label;
    String method;
    String employeeName;
    DateTime createdAt;
    double total;

    if (sale is LocalSale) {
      label = sale.items.isNotEmpty
          ? sale.items.first.productName +
              (sale.items.length > 1 ? ' + ${sale.items.length - 1} mas' : '')
          : 'Venta';
      method = sale.paymentMethod;
      employeeName = '';
      createdAt = sale.createdAt;
      total = sale.total;
    } else if (sale is Map) {
      final items = (sale['Items'] ?? sale['items'] ?? []) as List;
      if (items.isNotEmpty) {
        final first = items.first as Map;
        final name = (first['name'] ?? first['product_name'] ?? 'Producto') as String;
        label = items.length > 1 ? '$name + ${items.length - 1} mas' : name;
      } else {
        label = 'Venta';
      }
      method = (sale['payment_method'] as String?) ?? 'cash';
      employeeName = (sale['employee_name'] as String?) ?? '';
      createdAt = DateTime.tryParse(sale['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now();
      total = (sale['total'] as num?)?.toDouble() ?? 0;
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(_payIcon(method), color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  [
                    _payLabel(method, context),
                    if (employeeName.isNotEmpty) employeeName,
                    _timeAgo(createdAt),
                  ].join(' · '),
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(_formatCOP(total.round()),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success)),
        ],
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    const days = [
      'Lunes', 'Martes', 'Miércoles', 'Jueves',
      'Viernes', 'Sábado', 'Domingo'
    ];
    return '${days[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HERO HEADER DELEGATE
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final String ownerName;
  final String businessName;
  /// Tipos de negocio seleccionados por el dueño (uno o varios). El
  /// header los muestra como chip(s) clickeables debajo del nombre del
  /// negocio, antes del badge de sucursal. Vacío = no se muestra nada.
  final List<String> businessTypes;
  final String? branchName;
  final bool isStoreOpen;
  final bool loadingStoreStatus;
  final ValueChanged<bool> onToggleStore;
  final Future<void> Function() onLogout;
  /// Callback al tocar el chip de categoría — abre la pantalla donde
  /// el dueño puede cambiar o agregar tipos de negocio.
  final VoidCallback onEditBusinessTypes;
  final String todayLabel;

  _HeroHeaderDelegate({
    required this.topPadding,
    required this.ownerName,
    required this.businessName,
    this.businessTypes = const [],
    this.branchName,
    required this.isStoreOpen,
    required this.loadingStoreStatus,
    required this.onToggleStore,
    required this.onLogout,
    required this.onEditBusinessTypes,
    required this.todayLabel,
  });

  // Mapa label legible — espejo del grid de selección en
  // business_profile_screen.dart. Mantener sincronizados.
  static const _typeLabels = <String, String>{
    'tienda_barrio': 'Tienda de Barrio',
    'minimercado': 'Minimercado',
    'deposito_construccion': 'Depósito / Ferretería',
    'restaurante': 'Restaurante',
    'comidas_rapidas': 'Comidas Rápidas',
    'bar': 'Bar / Discoteca',
    'manufactura': 'Manufactura',
    'reparacion_muebles': 'Reparación / Servicios',
    'emprendimiento_general': 'Emprendimiento',
    // Legacy → mismo mapeo que _legacyTypeRemap en business_profile_screen.
    'muebles': 'Reparación / Servicios',
    'reparacion': 'Reparación / Servicios',
    'miscelanea': 'Emprendimiento',
  };

  String _labelFor(String type) => _typeLabels[type] ?? type;

  static const _heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF6366F1)],
  );

  // El cuerpo expandido incluye, además del saludo y la fila de
  // estado/fecha, la barra del trial (F009). 226 = 170 base + ~56 de
  // la barra; cuando el tenant es Pro la barra es `SizedBox.shrink`
  // y el espacio extra queda como aire — sin overflow a 360dp.
  // _collapsedBody = 60 reserva el avatar de 40dp + 8 padding superior
  // + 16 padding inferior (estándar Material). Antes era 52, lo que
  // dejaba el contenido pegado al borde redondeado inferior.
  static const double _expandedBody = 234;
  static const double _collapsedBody = 60;

  @override
  double get maxExtent => topPadding + _expandedBody;
  @override
  double get minExtent => topPadding + _collapsedBody;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final t = (shrinkOffset / range).clamp(0.0, 1.0);
    final detailsOpacity = (1.0 - t * 1.8).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: _heroGradient,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          boxShadow: t > 0.3
              ? [
                  BoxShadow(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          // Padding interno consistente expandido↔colapsado. Antes el
          // bottom era 8dp y el contenido quedaba pegado al borde
          // redondeado del gradiente al colapsar el header. Material 3
          // recomienda 16dp como mínimo para card content insets — eso
          // garantiza aire visual entre el avatar y el borde aunque el
          // header se compacte por el scroll.
          padding: EdgeInsets.fromLTRB(20, topPadding + 8, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Row 1: name + icons (always visible) ──────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ownerName,
                          style: TextStyle(
                            fontSize: 20 - (2 * t), // 20 → 18
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Business + branch name under owner name,
                        // fades and shrinks on collapse
                        if (detailsOpacity > 0)
                          Opacity(
                            opacity: detailsOpacity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  businessName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Chip(s) de categoría(s) del negocio.
                                // Acceso directo: tap → BusinessProfileScreen
                                // donde el dueño elige/agrega categorías.
                                if (businessTypes.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: onEditBusinessTypes,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.25),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.storefront_rounded,
                                                size: 12,
                                                color: Colors.white
                                                    .withValues(alpha: 0.9)),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                businessTypes
                                                    .map(_labelFor)
                                                    .join(' · '),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.2,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.edit_rounded,
                                                size: 11,
                                                color: Colors.white
                                                    .withValues(alpha: 0.7)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                Builder(
                                  builder: (ctx) {
                                    final bp = ctx.watch<BranchProvider>();
                                    final name = bp.currentBranch?.name ?? branchName ?? 'Principal';
                                    final multi = bp.isMultiBranch;
                                    return GestureDetector(
                                      onTap: multi ? () => _showBranchPicker(ctx, bp) : null,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '📍 $name',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white.withValues(alpha: 0.7),
                                              height: 1.2,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (multi)
                                            Icon(Icons.keyboard_arrow_down_rounded,
                                                size: 16,
                                                color: Colors.white.withValues(alpha: 0.6)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const OnlineOrdersBell(
                      iconColor: Color(0xFFFBBF24), size: 40),
                  _AccountMenuButton(
                    ownerName: ownerName,
                    businessName: businessName,
                    onLogout: onLogout,
                    iconColor: Colors.white,
                  ),
                ],
              ),
              // ── Expandable details (fade + shrink on scroll) ─────
              ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: detailsOpacity.clamp(0.0, 1.0),
                  child: Opacity(
                    opacity: detailsOpacity,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _StoreStatusPill(
                                isOpen: isStoreOpen,
                                loading: loadingStoreStatus,
                                onToggle: onToggleStore,
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.calendar_today_rounded,
                                  size: 12,
                                  color: Colors.white
                                      .withValues(alpha: 0.5)),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(todayLabel,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white
                                            .withValues(alpha: 0.5)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          // ── Barra del trial (Feature 009) ────────
                          // Acceso directo a la vista de planes. Se
                          // pinta sola: TRIAL → barra; FREE → prompt;
                          // PRO → `SizedBox.shrink` (no ocupa nada).
                          const SizedBox(height: 10),
                          const TrialBar(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HeroHeaderDelegate o) =>
      o.isStoreOpen != isStoreOpen ||
      o.loadingStoreStatus != loadingStoreStatus ||
      o.ownerName != ownerName ||
      o.businessName != businessName ||
      o.branchName != branchName ||
      o.todayLabel != todayLabel ||
      !_listEquals(o.businessTypes, businessTypes);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLASS CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _GlassCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
/// Account menu button on the dashboard header. Opens a bottom sheet
/// with the user's identity + workspace and a "Cerrar sesión" action.
/// Visible to every role — owners had logout inside Configuración,
/// but cashiers and waiters never reach that hub, so the only escape
/// from a session was wiping the app.
void _showBranchPicker(BuildContext context, BranchProvider provider) {
  HapticFeedback.lightImpact();
  final branches = provider.branches.where((b) => b.isActive).toList();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFD6D0C8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Seleccionar Sucursal',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...branches.map((b) {
            final isSelected = b.id == provider.currentBranchId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () {
                  HapticFeedback.lightImpact();
                  provider.selectBranch(b);
                  // Persist so next app start uses this branch
                  AuthService().saveBranchId(b.id);
                  Navigator.of(context).pop();
                },
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                tileColor: isSelected
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.grey.shade50,
                leading: Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.location_on_outlined,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                ),
                title: Text(b.name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isSelected ? AppTheme.primary : AppTheme.textPrimary)),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                    : null,
              ),
            );
          }),
        ],
      ),
    ),
  );
}

/// Icono de "Mi cuenta" en el AppBar del Dashboard.
///
/// Bug F022 follow-up: el botón antes era `StatelessWidget` que pintaba
/// SIEMPRE el ícono genérico `Icons.person_rounded`. La foto de perfil
/// solo se cargaba dentro del bottom-sheet — el usuario subía foto en
/// "Mi cuenta", se veía OK ahí, pero al cerrar el sheet el avatar del
/// Dashboard seguía con el ícono default. Ahora el botón también lee
/// la foto del Employee `is_owner` y la muestra circular, con refresh
/// automático tras cerrar el sheet (por si la subió o cambió).
class _AccountMenuButton extends StatefulWidget {
  final String ownerName;
  final String businessName;
  final Future<void> Function() onLogout;
  final Color iconColor;

  const _AccountMenuButton({
    required this.ownerName,
    required this.businessName,
    required this.onLogout,
    this.iconColor = AppTheme.primary,
  });

  @override
  State<_AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends State<_AccountMenuButton> {
  late final ApiService _api;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _loadOwnerPhoto();
  }

  Future<void> _loadOwnerPhoto() async {
    try {
      final employees = await _api.fetchEmployees();
      final owner = employees.firstWhere(
        (e) => (e['is_owner'] as bool? ?? false) == true,
        orElse: () => <String, dynamic>{},
      );
      final rawPhoto = (owner['photo_url'] as String?)?.trim();
      if (!mounted) return;
      setState(() {
        _photoUrl = (rawPhoto == null || rawPhoto.isEmpty) ? null : rawPhoto;
      });
    } catch (_) {
      // Silencio adrede: si la red falla, mantenemos el placeholder de
      // iniciales — el sheet hará un fetch nuevo cuando se abra y allí
      // se reporta el error si hace falta.
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = context.watch<RoleManager>().role.label;
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    return IconButton(
      tooltip: 'Mi cuenta',
      icon: hasPhoto
          ? ProfilePhotoAvatar(
              name: widget.ownerName,
              photoUrl: _photoUrl,
              diameter: 40,
              backgroundColor: widget.iconColor,
            )
          : Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_rounded,
                  color: widget.iconColor, size: 24),
            ),
      onPressed: () async {
        HapticFeedback.lightImpact();
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.white,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (ctx) => _AccountSheetContent(
            ownerName: widget.ownerName,
            businessName: widget.businessName,
            roleLabel: roleLabel,
            onLogout: widget.onLogout,
          ),
        );
        // Al cerrar el sheet, releemos por si subió/cambió la foto.
        // No depende del result del sheet — la lectura es barata y el
        // sheet no expone callback de cambio.
        if (mounted) await _loadOwnerPhoto();
      },
    );
  }
}

/// Body of the "Mi cuenta" bottom sheet.
///
/// Spec 022 / FR-01, FR-02, FR-04: the owner reaches their profile from
/// "Mi cuenta" (the header profile icon), not from the Empleados screen.
/// This sheet shows the owner's circular avatar and lets them load or
/// change their profile photo, reusing F019's [ProfilePhotoAvatar],
/// [ProfilePhotoPicker] and `ApiService.uploadEmployeePhoto`.
///
/// Spec 022 / FR-03, D2: the owner is the [Employee] with `is_owner`.
/// The id is resolved from the frontend by calling `fetchEmployees` and
/// picking the `is_owner` row — no backend `me` endpoint was needed.
class _AccountSheetContent extends StatefulWidget {
  const _AccountSheetContent({
    required this.ownerName,
    required this.businessName,
    required this.roleLabel,
    required this.onLogout,
  });

  final String ownerName;
  final String businessName;
  final String roleLabel;
  final Future<void> Function() onLogout;

  @override
  State<_AccountSheetContent> createState() => _AccountSheetContentState();
}

class _AccountSheetContentState extends State<_AccountSheetContent> {
  late final ApiService _api;

  /// UUID of the owner Employee — needed to upload the profile photo.
  String? _ownerEmployeeId;

  /// Persisted profile photo URL of the owner; advances after an upload.
  String? _photoUrl;

  /// True while resolving the owner id from `fetchEmployees`.
  bool _loading = true;

  /// Spanish message shown when the owner id could not be resolved.
  String? _resolveError;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _resolveOwner();
  }

  /// Resolves the owner Employee (the row with `is_owner == true`) so the
  /// profile-photo upload has a target UUID. Spec 022 / T-01, D2.
  Future<void> _resolveOwner() async {
    try {
      final employees = await _api.fetchEmployees();
      final owner = employees.firstWhere(
        (e) => (e['is_owner'] as bool? ?? false) == true,
        orElse: () => <String, dynamic>{},
      );
      if (!mounted) return;
      final id = (owner['id'] as String?)?.trim();
      final rawPhoto = (owner['photo_url'] as String?)?.trim();
      setState(() {
        _ownerEmployeeId = (id == null || id.isEmpty) ? null : id;
        _photoUrl = (rawPhoto == null || rawPhoto.isEmpty) ? null : rawPhoto;
        _resolveError = _ownerEmployeeId == null
            ? 'No pudimos cargar tu perfil. Intenta de nuevo.'
            : null;
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _resolveError = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Foto de perfil del dueño (Spec 022) ───────────
              Center(child: _buildProfilePhoto()),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.ownerName,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${widget.roleLabel} • ${widget.businessName}',
                            style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Spec F038 — acceso a settings de notificaciones desde
              // el menú de cuenta. Reemplaza el flujo automático del
              // PushOptinCard del Dashboard, que en iPhone Safari PWA
              // resultó no aparecer de forma confiable. Acá el tendero
              // entra explícitamente, ve el estado, activa y prueba.
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.notifications_active_rounded,
                      color: Color(0xFF6D28D9)),
                  label: const Text('Notificaciones',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6D28D9))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEDE9FE),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          const NotificationsSettingsScreen(),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout_rounded,
                      color: AppTheme.error),
                  label: const Text('Cerrar sesión',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.error)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppTheme.error.withValues(alpha: 0.08),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onLogout();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Owner avatar + photo picker, with graceful fallbacks while the
  /// owner id is loading or could not be resolved. Spec 022 / FR-01,
  /// FR-02, FR-04.
  Widget _buildProfilePhoto() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
      );
    }

    // Owner id could not be resolved: still show an avatar (initials)
    // plus a retry, never an empty hole (Constitution Art. I).
    if (_ownerEmployeeId == null) {
      return Column(
        children: [
          ProfilePhotoAvatar(
            name: widget.ownerName,
            photoUrl: _photoUrl,
            diameter: 104,
          ),
          const SizedBox(height: 10),
          Text(
            _resolveError ?? 'No pudimos cargar tu perfil.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('account_photo_retry'),
            onPressed: () {
              setState(() {
                _loading = true;
                _resolveError = null;
              });
              _resolveOwner();
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Reintentar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    }

    // Spec 022 / FR-04: ProfilePhotoPicker owns the picked-image preview
    // and the upload; on success it reports back the new URL so the
    // avatar refreshes immediately within this sheet.
    return ProfilePhotoPicker(
      key: const Key('account_photo_picker'),
      api: _api,
      employeeUuid: _ownerEmployeeId!,
      name: widget.ownerName.isEmpty ? 'Mi cuenta' : widget.ownerName,
      photoUrl: _photoUrl,
      isOwner: true,
      onUploaded: (url) {
        if (!mounted) return;
        setState(() => _photoUrl = url);
      },
    );
  }
}

/// Storefront open/closed pill rendered on the dashboard header next
/// to the tendero's greeting. The catálogo público (Next.js) reads
/// is_delivery_open to decide whether to allow add-to-cart, so this
/// control must be one-tap-away and visually unmissable. Gerontodiseño
/// choices: pill shape, high-contrast colours, emoji reinforces the

/// colour signal (colour-blind-safe), spinner covers PATCH latency,
/// tap disabled while loading to prevent double-fire.
class _StoreStatusPill extends StatelessWidget {
  final bool isOpen;
  final bool loading;
  final ValueChanged<bool> onToggle;

  const _StoreStatusPill({
    required this.isOpen,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isOpen
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.1);
    final border = isOpen
        ? const Color(0xFF4ADE80).withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.3);
    final fg = isOpen ? const Color(0xFF4ADE80) : Colors.white.withValues(alpha: 0.7);
    final label = isOpen ? 'Abierta 🟢' : 'Cerrada 🔴';

    return Semantics(
      key: const Key('dashboard_store_status_pill'),
      button: true,
      toggled: isOpen,
      label: isOpen
          ? 'Tienda online abierta, toca para cerrar'
          : 'Tienda online cerrada, toca para abrir',
      child: GestureDetector(
        onTap: loading ? null : () => onToggle(!isOpen),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                height: 22,
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.contain,
                        child: Switch(
                          value: isOpen,
                          onChanged: onToggle,
                          activeThumbColor: AppTheme.success,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
