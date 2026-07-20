// Spec: specs/107-dashboard-v2-resumen/spec.md
//
// Inicio v2 (reemplaza al dashboard actual para back-office): héroe azul con
// ventas de hoy + carrusel táctil, remate oblicuo, tarjetas con datos vivos,
// movimientos del día y barra inferior con el chulo de Vendi al centro.
// UNA sola llamada de resumen pinta todo (FR-01); las secciones profundas
// cargan al entrar. El dashboard anterior vive como "Todos los módulos"
// (paridad FR-10).
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/home_summary_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/financial_dashboard_screen.dart';
import '../history/sales_history_screen.dart';
import '../inventory/manage_inventory_screen.dart';
import '../onboarding/vendi/vendi_chat_screen.dart';
import '../pos/cuaderno_fiados_screen.dart';
import '../pos/pos_screen.dart';
import 'hero_carousel.dart';
import 'home_widgets.dart';

class HomeScreenV2 extends StatefulWidget {
  const HomeScreenV2({
    super.key,
    required this.ownerName,
    required this.businessName,
    this.summaryServiceOverride,
    this.capabilitiesOverride,
  });

  final String ownerName;
  final String businessName;

  /// Tests: inyectar servicio de resumen y capacidades sin red.
  final HomeSummaryService? summaryServiceOverride;
  final Set<String>? capabilitiesOverride;

  @override
  State<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends State<HomeScreenV2> {
  late final ApiService _api = ApiService(AuthService());
  late final HomeSummaryService _service = widget.summaryServiceOverride ??
      HomeSummaryService(fetch: _api.fetchDashboardSummary);

  HomeSummary _summary = HomeSummary.empty();
  bool _loaded = false;
  Set<String> _caps = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // UNA llamada (FR-01); capacidades desde el caché local de Auth (cero
    // peticiones extra — vienen del login/perfil ya sincronizados).
    final caps = widget.capabilitiesOverride ?? await _loadCaps();
    final s = await _service.load();
    if (!mounted) return;
    setState(() {
      _summary = s;
      _caps = caps;
      _loaded = true;
    });
  }

  Future<Set<String>> _loadCaps() async {
    try {
      final auth = AuthService();
      final flags = await auth.getFeatureFlags();
      return {if (flags.enableTables) 'tables'};
    } catch (_) {
      return const {};
    }
  }

  bool get _hasOperation =>
      _caps.contains('tables') ||
      _summary.inProgressTables > 0 ||
      _summary.inProgressOnline > 0;

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load()); // refresco al volver (barato: 1 llamada)
  }

  void _openAllModules() {
    _push(DashboardScreen(
      ownerName: widget.ownerName,
      businessName: widget.businessName,
    ));
  }

  void _openVendi() {
    _push(VendiChatScreen(
      kind: 'assist',
      onCompleted: () => Navigator.of(context).maybePop(),
      onNavigateRoute: _navigateFromVendi,
    ));
  }

  /// Rutas del catálogo cerrado de acciones (FR-08b navigate).
  void _navigateFromVendi(String route) {
    switch (route) {
      case 'pos':
        _push(const PosScreen());
      case 'inventario':
        _push(const ManageInventoryScreen());
      case 'fiados':
        _push(const CuadernoFiadosScreen());
      case 'historial':
        _push(const SalesHistoryScreen());
      case 'ganancias':
      case 'reportes':
        _push(const FinancialDashboardScreen());
      default:
        _openAllModules();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FB),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.primary,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _hero(),
              const HeroTail(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_summary.fromCache)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Sin conexión — datos de hace ${_summary.ageMinutes} min',
                          key: const Key('home_cache_notice'),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFD97706)),
                        ),
                      ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Su negocio hoy',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16.5, fontWeight: FontWeight.w800)),
                        ),
                        TextButton(
                          key: const Key('home_all_modules'),
                          onPressed: _openAllModules,
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact),
                          child: const Text('Todos los módulos ›',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_loaded)
                      LiveCards(
                        cards: buildLiveCards(
                          s: _summary,
                          hasOperation: _hasOperation,
                          onFiados: () => _push(const CuadernoFiadosScreen()),
                          onGanancias: () =>
                              _push(const FinancialDashboardScreen()),
                          onOperacion: _openAllModules,
                          onInventario: () =>
                              _push(const ManageInventoryScreen()),
                          onHistorial: () => _push(const SalesHistoryScreen()),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const Text('Movimientos de hoy',
                        style: TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    MovementsList(movements: _summary.movements),
                    const SizedBox(height: 110),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _navBar(),
      floatingActionButton: _vendiFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A4F80), AppTheme.primary, Color(0xFF2E97D4)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  color: Color(0xFF8FE9FB), size: 26),
              const SizedBox(width: 8),
              const Text('Vend',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              const Text('IA',
                  style: TextStyle(
                      color: Color(0xFF8FE9FB),
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              _iconBtn(
                key: 'home_bell',
                icon: Icons.notifications_none_rounded,
                badge: _summary.tasksUrgent > 0,
                onTap: _openAllModules,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ventas de hoy · ${_summary.salesCount} venta${_summary.salesCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5),
                    ),
                    Text(
                      '\$ ${formatCopHome(_summary.salesTotal)}',
                      key: const Key('home_sales_today'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 42,
                height: 42,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('home_new_sale'),
                    customBorder: const CircleBorder(),
                    onTap: () => _push(const PosScreen()),
                    child: const Icon(Icons.add,
                        color: AppTheme.primary, size: 24),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HeroCarousel(items: _carouselItems()),
        ],
      ),
    );
  }

  /// Vender y Catálogo fijos al frente; el resto según capacidades (FR-03).
  List<HeroCarouselItem> _carouselItems() {
    final items = <HeroCarouselItem>[
      HeroCarouselItem(
          key: 'vender',
          label: 'Vender',
          icon: Icons.shopping_cart_outlined,
          onTap: () => _push(const PosScreen())),
      HeroCarouselItem(
          key: 'catalogo',
          label: 'Catálogo',
          icon: Icons.public_outlined,
          onTap: _openAllModules),
      HeroCarouselItem(
          key: 'fiar',
          label: 'Fiar',
          icon: Icons.menu_book_outlined,
          onTap: () => _push(const CuadernoFiadosScreen())),
      HeroCarouselItem(
          key: 'inventario',
          label: 'Inventario',
          icon: Icons.inventory_2_outlined,
          onTap: () => _push(const ManageInventoryScreen())),
      HeroCarouselItem(
          key: 'historial',
          label: 'Historial',
          icon: Icons.receipt_long_outlined,
          onTap: () => _push(const SalesHistoryScreen())),
      HeroCarouselItem(
          key: 'ganancias',
          label: 'Ganancias',
          icon: Icons.trending_up_rounded,
          onTap: () => _push(const FinancialDashboardScreen())),
      if (_caps.contains('tables'))
        HeroCarouselItem(
            key: 'mesas',
            label: 'Mesas',
            icon: Icons.table_restaurant_outlined,
            onTap: _openAllModules),
    ];
    return items;
  }

  Widget _iconBtn({
    required String key,
    required IconData icon,
    bool badge = false,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.white.withValues(alpha: .16),
        shape: const CircleBorder(),
        child: InkWell(
          key: Key(key),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              if (badge)
                Positioned(
                  top: 8,
                  right: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF5A5A), shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBar() {
    Widget item(String key, IconData icon, String label, VoidCallback onTap,
        {bool active = false}) {
      final color = active ? AppTheme.primary : const Color(0xFF8AA2B2);
      return Expanded(
        child: InkWell(
          key: Key(key),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      );
    }

    return BottomAppBar(
      color: Colors.white,
      elevation: 12,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        children: [
          item('nav_inicio', Icons.home_outlined, 'Inicio', () {},
              active: true),
          item('nav_reportes', Icons.bar_chart_rounded, 'Reportes',
              () => _push(const FinancialDashboardScreen())),
          const SizedBox(width: 72), // hueco del FAB
          item('nav_inventario', Icons.inventory_2_outlined, 'Inventario',
              () => _push(const ManageInventoryScreen())),
          item('nav_negocio', Icons.storefront_outlined, 'Mi negocio',
              _openAllModules),
        ],
      ),
    );
  }

  Widget _vendiFab() {
    return SizedBox(
      width: 68,
      height: 68,
      child: FloatingActionButton(
        key: const Key('vendi_fab'),
        onPressed: _openVendi,
        elevation: 6,
        shape: const CircleBorder(),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primary, Color(0xFF2E97D4), AppTheme.accent],
            ),
            boxShadow: [
              BoxShadow(
                  color: Color(0x730E6BA8),
                  blurRadius: 18,
                  offset: Offset(0, 8)),
            ],
          ),
          child: const Center(
            child: Icon(Icons.check_rounded, color: Colors.white, size: 34),
          ),
        ),
      ),
    );
  }
}
