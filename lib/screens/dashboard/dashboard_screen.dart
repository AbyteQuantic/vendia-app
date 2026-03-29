import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/dashboard_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/stat_card.dart';
import '../auth/login_screen.dart';
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
          child: RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: _refresh,
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
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
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
                                color: AppTheme.primary.withOpacity(0.1),
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

                // ── Fecha ─────────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 18, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            _todayLabel(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Stats del día ─────────────────────────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 28, 24, 14),
                    child: Text('Resumen del día',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary)),
                  ),
                ),

                SliverToBoxAdapter(
                  child: FutureBuilder<DashboardStats>(
                    future: _statsFuture,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _ErrorBanner(
                          message: 'No se pudo cargar el resumen.',
                          onRetry: _refresh,
                        );
                      }
                      if (!snap.hasData) return const _StatsShimmer();

                      final s = snap.data!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            StatCard(
                              label: 'Ventas de hoy',
                              value: s.formattedTotal,
                              icon: Icons.payments_rounded,
                              iconColor: AppTheme.primary,
                              backgroundColor:
                                  AppTheme.primary.withOpacity(0.06),
                              trend: s.trend,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: StatCard(
                                    label: 'Transacciones',
                                    value: '${s.transactionCount}',
                                    icon: Icons.receipt_long_rounded,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: StatCard(
                                    label: 'Más vendido',
                                    value: s.topProduct,
                                    icon: Icons.star_rounded,
                                    iconColor: const Color(0xFFF59E0B),
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
                    padding: EdgeInsets.fromLTRB(24, 32, 24, 4),
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
                      if (snap.hasError) {
                        return _ErrorBanner(
                          message: 'No se pudieron cargar las ventas.',
                          onRetry: _refresh,
                        );
                      }
                      if (!snap.hasData) return const _TransactionsShimmer();

                      final sales = snap.data!;
                      if (sales.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
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
                          separatorBuilder: (_, __) => Divider(
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
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                    child: Semantics(
                      button: true,
                      label: 'Registrar nueva venta',
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
              color: AppTheme.primary.withOpacity(0.1),
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.error.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppTheme.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppTheme.error, fontSize: 18)),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Reintentar',
                  style: TextStyle(color: AppTheme.primary, fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const ShimmerBox.full(height: 130, borderRadius: 24),
          const SizedBox(height: 16),
          Row(
            children: const [
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
