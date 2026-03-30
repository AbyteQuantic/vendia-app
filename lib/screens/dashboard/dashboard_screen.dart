import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../config/api_config.dart';
import '../../database/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/dashboard_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/stat_card.dart';
import '../auth/login_screen.dart';
import '../inventory/add_merchandise_screen.dart';
import '../pos/pos_screen.dart';

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
  late final DashboardService _service;

  late Future<DashboardStats> _statsFuture;
  late Future<List<RecentSale>> _salesFuture;
  late Future<_InventorySummary> _inventoryFuture;

  @override
  void initState() {
    super.initState();
    final auth = AuthService();
    _service = DashboardService(
      Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      )),
      auth,
    );
    _load();
  }

  void _load() {
    _statsFuture = _service.fetchStats();
    _salesFuture = _service.fetchRecentSales();
    _inventoryFuture = _loadInventorySummary();
  }

  Future<_InventorySummary> _loadInventorySummary() async {
    try {
      // Intentar desde DB local primero
      final localProducts = await DatabaseService.instance.getAllProducts();
      if (localProducts.isNotEmpty) {
        final total = localProducts.length;
        final incomplete = localProducts.where((p) =>
            p.price <= 0 || p.imageUrl == null || p.imageUrl!.isEmpty).length;
        return _InventorySummary(total: total, incomplete: incomplete);
      }

      // Fallback: consultar al backend
      final token = await AuthService().getToken();
      final res = await Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      )).get(
        '/api/v1/products',
        queryParameters: {'page': 1, 'limit': 1},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final total = res.data['total'] as int? ?? 0;
      return _InventorySummary(total: total, incomplete: 0);
    } catch (_) {
      return const _InventorySummary(total: 0, incomplete: 0);
    }
  }

  Future<void> _refresh() async {
    setState(() => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ScrollConfiguration(
          // Desactiva el StretchingOverscrollIndicator de Android API 31+
          // que deformaba todos los componentes al hacer pull-down.
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: RefreshIndicator.adaptive(
            color: AppTheme.primary,
            onRefresh: _refresh,
            displacement: 40,
            edgeOffset: 10,
            child: CustomScrollView(
              // ClampingScrollPhysics: previene el stretch/bounce nativo;
              // AlwaysScrollable: mantiene el pull-to-refresh funcionando.
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                // ── Header ────────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting(),
                                style: const TextStyle(
                                    fontSize: 18,
                                    color: AppTheme.textSecondary),
                              ),
                              Text(
                                widget.ownerName,
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.businessName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: 'Menú de opciones',
                          child: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'logout') {
                                await AuthService().logout();
                                if (!context.mounted) return;
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen()),
                                  (_) => false,
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'logout',
                                child: Row(
                                  children: [
                                    Icon(Icons.logout_rounded,
                                        color: AppTheme.error, size: 20),
                                    SizedBox(width: 10),
                                    Text('Cerrar sesión',
                                        style: TextStyle(
                                            color: AppTheme.error,
                                            fontSize: 18)),
                                  ],
                                ),
                              ),
                            ],
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.storefront_rounded,
                                  color: AppTheme.primary, size: 28),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Fecha + Título ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          _todayLabel(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: FutureBuilder<DashboardStats>(
                    future: _statsFuture,
                    builder: (context, snap) {
                      if (!snap.hasData && !snap.hasError) {
                        return const _StatsShimmer();
                      }

                      final s = snap.data ??
                          const DashboardStats(
                            totalSalesToday: 0,
                            transactionCount: 0,
                            topProduct: '—',
                            trend: 'primer día',
                          );
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            // Fila 1: Ventas + Transacciones
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: StatCard(
                                    label: 'Ventas de hoy',
                                    value: s.formattedTotal,
                                    icon: Icons.payments_rounded,
                                    iconColor: AppTheme.primary,
                                    backgroundColor: AppTheme.primary
                                        .withValues(alpha: 0.06),
                                    trend: s.trend,
                                    compact: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: StatCard(
                                    label: 'Ventas',
                                    value: '${s.transactionCount}',
                                    icon: Icons.receipt_long_rounded,
                                    compact: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Fila 2: Más vendido + Inventario
                            Row(
                              children: [
                                Expanded(
                                  child: StatCard(
                                    label: 'Más vendido',
                                    value: s.topProduct,
                                    icon: Icons.star_rounded,
                                    iconColor: const Color(0xFFF59E0B),
                                    compact: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FutureBuilder<_InventorySummary>(
                                    future: _inventoryFuture,
                                    builder: (context, invSnap) {
                                      final inv = invSnap.data ??
                                          const _InventorySummary(
                                              total: 0, incomplete: 0);
                                      return _InventoryCardCompact(
                                        summary: inv,
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const AddMerchandiseScreen(),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── Últimas ventas ────────────────────────────────────────────
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

                SliverToBoxAdapter(
                  child: FutureBuilder<List<RecentSale>>(
                    future: _salesFuture,
                    builder: (context, snap) {
                      if (!snap.hasData && !snap.hasError) {
                        return const _TransactionsShimmer();
                      }

                      // Si falla el API, mostrar lista vacía
                      final sales = snap.data ?? [];
                      if (sales.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Center(
                            child: Text(
                              'Aún no hay ventas hoy.\n¡Registre la primera!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18, color: AppTheme.textSecondary),
                            ),
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGrey,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: ListView.separated(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: sales.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 76,
                            color: AppTheme.borderColor,
                          ),
                          itemBuilder: (_, i) => _SaleTile(sale: sales[i]),
                        ),
                      );
                    },
                  ),
                ),

                // ── CTA: Nueva venta ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PosScreen(),
                        ));
                        _refresh();
                      },
                      icon: const Icon(Icons.add_rounded, size: 26),
                      label: const Text('Registrar nueva venta'),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 40),
                ),
              ],
            ),
          ),
        ),
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
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    const days = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo'
    ];
    return '${days[now.weekday - 1]}, ${now.day} de ${months[now.month - 1]}';
  }
}

// ── Widgets auxiliares ─────────────────────────────────────────────────────────

class _SaleTile extends StatelessWidget {
  final RecentSale sale;
  const _SaleTile({required this.sale});

  IconData get _payIcon => switch (sale.paymentMethod) {
        'transfer' => Icons.phone_android_rounded,
        'card' => Icons.credit_card_rounded,
        _ => Icons.payments_rounded,
      };

  @override
  Widget build(BuildContext context) {
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
            child: Icon(_payIcon, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  sale.timeAgo,
                  style: const TextStyle(
                      fontSize: 18, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            sale.formattedTotal,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.success),
          ),
        ],
      ),
    );
  }
}


class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          ShimmerBox.full(height: 130, borderRadius: 24),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: ShimmerBox.full(height: 110, borderRadius: 24)),
              SizedBox(width: 16),
              Expanded(child: ShimmerBox.full(height: 110, borderRadius: 24)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionsShimmer extends StatelessWidget {
  const _TransactionsShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: List.generate(4, (_) => const ShimmerTransactionRow()),
      ),
    );
  }
}

// ── Inventario ──────────────────────────────────────────────────────────────

class _InventorySummary {
  final int total;
  final int incomplete;

  const _InventorySummary({required this.total, required this.incomplete});

  int get complete => total - incomplete;
}

class _InventoryCardCompact extends StatelessWidget {
  final _InventorySummary summary;
  final VoidCallback onTap;

  const _InventoryCardCompact({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasIncomplete = summary.incomplete > 0;
    final iconColor = hasIncomplete ? AppTheme.warning : AppTheme.primary;
    final value = summary.total == 0
        ? 'Vacío'
        : '${summary.total} ref.';

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
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.inventory_2_rounded,
                      color: iconColor, size: 22),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Inventario',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            if (hasIncomplete) ...[
              const SizedBox(height: 2),
              Text(
                '${summary.incomplete} pendiente${summary.incomplete == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
