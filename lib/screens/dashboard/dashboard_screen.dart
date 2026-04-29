import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_sale.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/role_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/online_orders_bell.dart';
import '../../widgets/stat_card.dart';
import '../auth/login_screen.dart';
import '../inventory/add_merchandise_screen.dart';
import '../online_store/promo_management_screen.dart';
import '../pos/pos_screen.dart';
import '../../database/sync/sales_sync.dart';
import '../../widgets/sync_status_banner.dart';
import 'admin_hub_screen.dart';
import 'financial_dashboard_screen.dart';
import 'product_insights_screen.dart';

// ── Dashboard Data (computed from Isar) ─────────────────────────────────────

class _DashboardData {
  final double totalToday;
  final int txCount;
  final String topProduct;
  final int prodCount;
  final List<LocalSale> recentSales;

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

  // Reactive data holder
  _DashboardData _data = const _DashboardData(
    totalToday: 0, txCount: 0, topProduct: '—', prodCount: 0, recentSales: [],
  );

  // Marketing Hub badge. Loaded lazily from the backend; failures
  // degrade silently (keep 0) so the dashboard still renders offline.
  int _activePromosCount = 0;

  // Storefront open/closed flag. The catálogo público reacts to this
  // value (add-to-cart disabled when closed) so it must be obvious
  // on the dashboard header and fast to flip. Loaded from the backend
  // on mount; failures keep the default `false`.
  bool _isStoreOpen = false;
  bool _loadingStoreStatus = false;

  @override
  void initState() {
    super.initState();
    _loadData(); // Initial load from Isar
    _syncFromServer(); // Pull fresh data from backend
    _loadActivePromosCount();
    _loadStoreStatus();

    final isar = _db.isar;

    // Listen for changes in sales & products collections
    _salesSub = isar.localSales
        .watchLazy(fireImmediately: false)
        .listen((_) => _loadData());

    _productsSub = isar.localProducts
        .watchLazy(fireImmediately: false)
        .listen((_) => _loadData());
  }

  /// Pull sales from the server so the dashboard is up to date even
  /// after a fresh login or tenant switch that cleared Isar.
  Future<void> _syncFromServer() async {
    try {
      await SalesSyncService.fullSync();
      // Isar watchers auto-trigger _loadData() when new rows land.
    } catch (_) {
      // Offline — dashboard still renders from whatever is local.
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

  /// Best-effort fetch of active promotions for the Marketing Hub badge.
  /// Non-blocking: any failure (offline, 401, backend not configured)
  /// keeps the count at 0 and the badge hidden.
  Future<void> _loadActivePromosCount() async {
    try {
      final api = ApiService(AuthService());
      final promos = await api.fetchPromotions();
      final active = promos.where((p) {
        final v = p['active'] ?? p['is_active'] ?? p['enabled'];
        return v is bool ? v : true;
      }).length;
      if (mounted) setState(() => _activePromosCount = active);
    } catch (_) {
      // Offline / not configured — keep badge hidden.
    }
  }

  @override
  void dispose() {
    _salesSub.cancel();
    _productsSub.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final sales = await _db.getSalesToday();
    sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final allProducts = await _db.getAllProducts();
    final prodCount = allProducts.length;

    final totalToday = sales.fold<double>(0, (sum, s) => sum + s.total);
    final top = _topProduct(sales);

    if (mounted) {
      setState(() {
        _data = _DashboardData(
          totalToday: totalToday,
          txCount: sales.length,
          topProduct: top,
          prodCount: prodCount,
          recentSales: sales.take(10).toList(),
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

  String _payLabel(String method) => switch (method) {
        'transfer' => 'Transferencia',
        'nequi' => 'Nequi',
        'daviplata' => 'Daviplata',
        'card' => 'Tarjeta',
        'credit' => 'Fiado',
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

  // ── Gradient constants ───────────────────────────────────────────
  static const _heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF6366F1)],
  );

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
                  isStoreOpen: _isStoreOpen,
                  loadingStoreStatus: _loadingStoreStatus,
                  onToggleStore: _toggleStoreStatus,
                  onLogout: _onLogout,
                  todayLabel: _todayLabel(),
                ),
              ),

              // ── Glass Stats Cards ──────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
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

              // ── Quick Actions ───────────────────────────────────
              SliverToBoxAdapter(
                child: !context
                        .watch<RoleManager>()
                        .canManageBusinessSettings
                    ? const SizedBox.shrink()
                    : Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: _GlassCard(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AdminHubScreen(),
                      ));
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.settings_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ajustes de mi Negocio',
                                  style: TextStyle(fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary)),
                              Text('Mesas, Fiados, Empleados y Perfil',
                                  style: TextStyle(fontSize: 14,
                                      color: AppTheme.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Color(0xFF3B82F6), size: 24),
                      ],
                    ),
                  ),
                ),
              ),

                // ── Marketing Hub Card ──────────────────────────────
                // Full-width entry point for the SaaS Phase 1 marketing
                // module (combos, AI banners, online catalog share).
                // Mirrors the "Ajustes de mi Negocio" card styling so
                // the dashboard reads as a coherent stack of hubs.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    child: _MarketingHubCard(
                      activePromos: _activePromosCount,
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PromoManagementScreen(),
                        ));
                        _loadActivePromosCount();
                      },
                    ),
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

  Widget _buildSaleTile(LocalSale sale) {
    final label = sale.items.isNotEmpty
        ? sale.items.first.productName +
            (sale.items.length > 1
                ? ' + ${sale.items.length - 1} más'
                : '')
        : 'Venta';

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
            child: Icon(_payIcon(sale.paymentMethod),
                color: AppTheme.primary, size: 24),
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
                  '${_payLabel(sale.paymentMethod)} · ${_timeAgo(sale.createdAt)}',
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(_formatCOP(sale.total.round()),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success)),
        ],
      ),
    );
  }

  String _greeting() {
    final h = TimeOfDay.now().hour;
    if (h < 12) return '¡Buenos días! ☀️';
    if (h < 18) return '¡Buenas tardes! 👋';
    return '¡Buenas noches! 🌙';
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
  final bool isStoreOpen;
  final bool loadingStoreStatus;
  final ValueChanged<bool> onToggleStore;
  final Future<void> Function() onLogout;
  final String todayLabel;

  _HeroHeaderDelegate({
    required this.topPadding,
    required this.ownerName,
    required this.businessName,
    required this.isStoreOpen,
    required this.loadingStoreStatus,
    required this.onToggleStore,
    required this.onLogout,
    required this.todayLabel,
  });

  static const double _expandedBody = 156;
  static const double _collapsedBody = 52;

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
          gradient: _DashboardScreenState._heroGradient,
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
          padding: EdgeInsets.fromLTRB(20, topPadding + 6, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        // Business name sits right under owner name,
                        // fades and shrinks on collapse
                        if (detailsOpacity > 0)
                          Opacity(
                            opacity: detailsOpacity,
                            child: Text(
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
              // ── Expandable details (fade out on scroll) ────────
              if (detailsOpacity > 0) ...[
                const SizedBox(height: 8),
                Opacity(
                  opacity: detailsOpacity,
                  child: Row(
                    children: [
                      _StoreStatusPill(
                        isOpen: isStoreOpen,
                        loading: loadingStoreStatus,
                        onToggle: onToggleStore,
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: Colors.white.withValues(alpha: 0.5)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(todayLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ],
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
      o.todayLabel != todayLabel;
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

// ═══════════════════════════════════════════════════════════════════════════════
// INVENTORY CARD (legacy — kept for compat, not used by the new layout)
// ═══════════════════════════════════════════════════════════════════════════════

class _InventoryCardCompact extends StatelessWidget {
  final int total;
  final VoidCallback onTap;

  const _InventoryCardCompact({required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? 'Vacío' : '$total ref.';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.inventory_2_rounded,
                      color: AppTheme.primary, size: 22),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Inventario',
                style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKETING HUB CARD
// ═══════════════════════════════════════════════════════════════════════════════

/// Full-width entry point for the SaaS Phase 1 marketing module.
///
/// Styled to mirror the "Ajustes de mi Negocio" card (same padding,
/// radius, chevron, subtitle hierarchy) but tinted in the accent
/// purple so it reads as a distinct, higher-energy hub over a neutral
/// settings row. Badge surfaces the count of active promotions when
/// the backend is reachable; stays hidden when count is 0.
class _MarketingHubCard extends StatelessWidget {
  final int activePromos;
  final VoidCallback onTap;

  const _MarketingHubCard({
    required this.activePromos,
    required this.onTap,
  });

  // Accent purple — intentionally different from AppTheme.primary so
  // this hub stands apart from the settings card above it.
  static const Color _accent = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final badgeLabel = activePromos == 1
        ? '1 promo activa'
        : '$activePromos promos activas';

    return Semantics(
      button: true,
      label: 'Catálogo y Promos. $badgeLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('btn_marketing_hub'),
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      color: _accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + badge in a Wrap so the badge breaks
                      // to a second line on 360dp instead of squeezing
                      // the title into "Catálogo ..." with ellipsis.
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '📢 Catálogo y Promos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (activePromos > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                badgeLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Cree combos, banners con IA y comparta su tienda online.',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: _accent, size: 26),
              ],
            ),
          ),
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
class _AccountMenuButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final roleLabel = context.watch<RoleManager>().role.label;
    return IconButton(
      tooltip: 'Mi cuenta',
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person_rounded,
            color: iconColor, size: 24),
      ),
      onPressed: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (ctx) => SafeArea(
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
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: AppTheme.primary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ownerName,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('$roleLabel • $businessName',
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
                        Navigator.of(ctx).pop();
                        await onLogout();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Storefront open/closed pill rendered on the dashboard header next
/// to the tendero's greeting. The catálogo público (Next.js) reads
/// is_delivery_open to decide whether to allow add-to-cart, so this
/// control must be one-tap-away and visually unmissable. Gerontodiseño
/// choices: pill shape, high-contrast colours, emoji reinforces the
/// Tiny dot indicator for the collapsed header — just a green/red circle.
class _StoreStatusDot extends StatelessWidget {
  final bool isOpen;
  const _StoreStatusDot({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOpen ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
      ),
    );
  }
}

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
                          activeColor: AppTheme.success,
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
