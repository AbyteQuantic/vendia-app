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
import '../../widgets/restricted_action.dart';
import '../../widgets/stat_card.dart';
import '../inventory/add_merchandise_screen.dart';
import '../online_store/promo_management_screen.dart';
import '../pos/pos_screen.dart';
import '../../widgets/sync_status_banner.dart';
import 'admin_hub_screen.dart';
import 'financial_dashboard_screen.dart';

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
    _loadData(); // Initial load
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(child: ScrollConfiguration(
          behavior:
              ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: RefreshIndicator.adaptive(
            color: AppTheme.primary,
            onRefresh: _refresh,
            displacement: 40,
            edgeOffset: 10,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                // ── Header ──────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting(),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      color: AppTheme.textSecondary)),
                              Text(widget.ownerName,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(widget.businessName,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StoreStatusPill(
                          isOpen: _isStoreOpen,
                          loading: _loadingStoreStatus,
                          onToggle: _toggleStoreStatus,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Date ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(_todayLabel(),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ),

                // ── Stats Cards (REACTIVE) ──────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // Row 1: Sales total + count
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Material(
                                color: Colors.transparent,
                                child: Builder(builder: (ctx) {
                                  final canOpen = ctx
                                      .watch<RoleManager>()
                                      .canSeeFinances;
                                  return RestrictedAction(
                                    allowed: canOpen,
                                    deniedMessage:
                                        'La tarjeta de Finanzas y Rentabilidad solo la ve el propietario del negocio.',
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const FinancialDashboardScreen()));
                                    },
                                    child: StatCard(
                                      label: 'Ventas de hoy',
                                      value: _formatCOP(
                                          _data.totalToday.round()),
                                      icon: Icons.payments_rounded,
                                      iconColor: AppTheme.primary,
                                      backgroundColor: AppTheme.primary
                                          .withValues(alpha: 0.06),
                                      trend: _data.txCount > 0
                                          ? '${_data.txCount} venta${_data.txCount > 1 ? 's' : ''}'
                                          : 'primer día',
                                      compact: true,
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => HapticFeedback.lightImpact(),
                                  child: StatCard(
                                    label: 'Ventas',
                                    value: '${_data.txCount}',
                                    icon: Icons.receipt_long_rounded,
                                    compact: true,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Row 2: Top product + Inventory
                        Row(
                          children: [
                            Expanded(
                              child: StatCard(
                                label: 'Más vendido',
                                value: _data.topProduct,
                                icon: Icons.star_rounded,
                                iconColor: const Color(0xFFF59E0B),
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _InventoryCardCompact(
                                total: _data.prodCount,
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AddMerchandiseScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Settings Card (owner/admin only) ─────────────────
                SliverToBoxAdapter(
                  child: !context
                          .watch<RoleManager>()
                          .canManageBusinessSettings
                      ? const SizedBox.shrink()
                      : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const AdminHubScreen(),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.settings_rounded,
                                    color: AppTheme.primary, size: 26),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Ajustes de mi Negocio',
                                        style: TextStyle(fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary)),
                                    Text('Mesas, Fiados, Empleados y Perfil',
                                        style: TextStyle(fontSize: 14,
                                            color: AppTheme.textSecondary)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: AppTheme.primary, size: 26),
                            ],
                          ),
                        ),
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
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
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: AppTheme.background,
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
// INVENTORY CARD
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
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              '📢 Catálogo y Promos',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (activePromos > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                badgeLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Cree combos, banners con IA y comparta su tienda online.',
                        style: TextStyle(
                          fontSize: 14,
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
        ? AppTheme.success.withValues(alpha: 0.12)
        : Colors.grey.shade100;
    final border = isOpen
        ? AppTheme.success.withValues(alpha: 0.4)
        : Colors.grey.shade300;
    final fg = isOpen ? AppTheme.success : AppTheme.textSecondary;
    final label = isOpen ? 'Tienda Abierta 🟢' : 'Tienda Cerrada 🔴';

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
