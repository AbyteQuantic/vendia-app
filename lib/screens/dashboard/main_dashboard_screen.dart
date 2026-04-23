import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branch_provider.dart';
import '../../services/panic_trigger_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panic_button.dart';
import '../../widgets/sync_status_banner.dart';
import '../admin/admin_hub_screen.dart';
import '../fiar/fiar_screen.dart';
import '../inventory/add_merchandise_screen.dart';
import '../inventory/expiring_products_screen.dart';
import '../tables/tables_screen.dart';
import 'branches_list_screen.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  String _chargeMode = 'pre_payment';
  int _expiringCount = 0;
  // Feature flags drive which cards the dashboard renders (MESAS, KDS,
  // service-first modules). Resolved once on mount because the blob
  // only changes across a fresh login.
  FeatureFlags _flags = const FeatureFlags();

  @override
  void initState() {
    super.initState();
    _loadChargeMode();
    _loadExpiringCount();
    _loadFeatureFlags();
  }

  Future<void> _loadChargeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('vendia_charge_mode') ?? 'pre_payment';
    if (mounted) setState(() => _chargeMode = mode);
  }

  Future<void> _loadFeatureFlags() async {
    final flags = await AuthService().getFeatureFlags();
    if (mounted) setState(() => _flags = flags);
  }

  /// Loads the count of products expiring within the backend's warning
  /// window (currently 7 days). Non-blocking — failures degrade silently
  /// so the dashboard still renders when offline.
  Future<void> _loadExpiringCount() async {
    try {
      final api = ApiService(AuthService());
      final list = await api.fetchExpiringProducts();
      if (mounted) setState(() => _expiringCount = list.length);
    } catch (_) {
      // Offline / not configured — keep count at 0.
    }
  }

  void _openExpiringList() {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
              builder: (_) => const ExpiringProductsScreen()),
        )
        .then((_) => _loadExpiringCount());
  }

  @override
  Widget build(BuildContext context) {
    // MESAS shows when the tenant enabled tables in onboarding (food
    // stack: restaurante / comidas_rapidas / bar) OR the legacy
    // post_payment charge_mode is active. The feature flag is the
    // authoritative signal; charge_mode is kept as a fallback so
    // pre-migration-021 tenants still see their Mesas button.
    final isPostPayment =
        _flags.enableTables || _chargeMode == 'post_payment';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Pantalla principal de VendIA',
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      // Logo + Bell row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.point_of_sale_rounded,
                                color: Colors.white, size: 40),
                          ),
                          const Spacer(),
                          // Botón de pánico silencioso
                          PanicButton(
                            onPanicTriggered: PanicTriggerService.trigger,
                          ),
                          if (_flags.enableKDS) const SizedBox(width: 8),
                          // KDS Notification bell — only rendered for
                          // food-stack tenants (enable_kds). Retail
                          // tiendas never need a pedidos panel so we
                          // drop the bell entirely instead of showing a
                          // "proximamente" snackbar.
                          if (_flags.enableKDS)
                          Semantics(
                            button: true,
                            label: 'Pedidos pendientes, 2 notificaciones',
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Proximamente: Panel de pedidos',
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ),
                                );
                              },
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: Stack(
                                  children: [
                                    const Center(
                                      child: Icon(
                                        Icons.notifications_rounded,
                                        color: AppTheme.textPrimary,
                                        size: 32,
                                      ),
                                    ),
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.error,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          '2',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'VendIA',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '¿Qué desea hacer hoy?',
                        style: TextStyle(
                            fontSize: 18, color: AppTheme.textSecondary),
                      ),
                      // Phase-6 branch indicator. The chip reads from
                      // BranchProvider which is kept in sync with
                      // ApiService.currentBranchId, so whatever the
                      // user sees here is exactly the scope the next
                      // inventory/sales/fiado call will use.
                      const SizedBox(height: 10),
                      const _CurrentBranchChip(),
                      if (_expiringCount > 0) ...[
                        const SizedBox(height: 16),
                        _ExpiringAlertCard(
                          count: _expiringCount,
                          onTap: _openExpiringList,
                        ),
                      ],
                      const SizedBox(height: 32),
                      Expanded(
                        child: Column(
                          children: [
                            // Top row: VENDER + FIAR (or MESAS + FIAR for post_payment)
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: Key(isPostPayment
                                          ? 'btn_mesas'
                                          : 'btn_vender'),
                                      label: isPostPayment ? 'MESAS' : 'VENDER',
                                      icon: isPostPayment
                                          ? Icons.table_restaurant_rounded
                                          : Icons.shopping_cart_rounded,
                                      color: AppTheme.primary,
                                      onTap: () {
                                        if (isPostPayment) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const TablesScreen()),
                                          );
                                        } else {
                                          Navigator.of(context)
                                              .pushNamed('/pos');
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: const Key('btn_fiar'),
                                      label: 'FIAR',
                                      icon: Icons.menu_book_rounded,
                                      color: const Color(0xFFF59E0B),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => const FiarScreen()),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Middle row: INVENTARIO (+ VENDER if post_payment)
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  if (isPostPayment) ...[
                                    Expanded(
                                      child: _DashButton(
                                        keyVal: const Key('btn_vender'),
                                        label: 'VENDER',
                                        icon: Icons.shopping_cart_rounded,
                                        color: const Color(0xFF7C3AED),
                                        onTap: () => Navigator.of(context)
                                            .pushNamed('/pos'),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: const Key('btn_inventario'),
                                      label: 'INVENTARIO',
                                      icon: Icons.inventory_2_rounded,
                                      color: const Color(0xFF7C3AED),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AddMerchandiseScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: const Key('btn_administrar'),
                                      label: 'ADMINISTRAR',
                                      icon: Icons.settings_rounded,
                                      color: const Color(0xFF059669),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AdminHubScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashButton extends StatelessWidget {
  final Key keyVal;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DashButton({
    required this.keyVal,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: keyVal,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 56),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red/orange alert card shown on the dashboard when at least one
/// product is close to expiring. Large tap target and gradient styling
/// match the dashboard's existing visual language (buttons use the same
/// gradient idiom) so it reads as a first-class action, not decoration.
class _ExpiringAlertCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ExpiringAlertCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? 'Tiene 1 producto a punto de vencer'
        : 'Tiene $count productos a punto de vencer';
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEF4444), Color(0xFFF59E0B)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tóquelo para ver la lista',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip showing the currently-active sede right under the dashboard
/// greeting. The widget's job is visibility + navigation: tap sends
/// the user to BranchesListScreen where multi-sede tenants can pick
/// another sede. Single-sede tenants see the chip too but the tap
/// lands on the same list (which is perfectly usable for them).
///
/// The chip reads from BranchProvider — the same source of truth
/// ApiService.currentBranchId mirrors — so whatever label the user
/// sees here is exactly the scope the next /products / /sales /
/// /credits call will carry.
class _CurrentBranchChip extends StatelessWidget {
  const _CurrentBranchChip();

  @override
  Widget build(BuildContext context) {
    // The Provider may not be installed in every test tree. Guard
    // with a try so `MainDashboardScreen` still renders cleanly in
    // the `main_dashboard_test.dart` smoke tests that don't inject
    // a BranchProvider above it.
    BranchProvider? provider;
    try {
      provider = context.watch<BranchProvider>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    final current = provider.currentBranch;
    if (current == null) {
      // No sede loaded yet — the dashboard just mounted and the
      // branches fetch is still in flight. Render nothing rather
      // than a "Sin sede" label that would blink for a split second.
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: 'Operando en ${current.name}. Toque para cambiar de sede.',
      child: GestureDetector(
        key: const Key('dashboard_branch_chip'),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BranchesListScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📍', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Operando en: ${current.name}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              if (provider.isMultiBranch) ...[
                const SizedBox(width: 6),
                const Icon(Icons.swap_horiz_rounded,
                    size: 18, color: AppTheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
