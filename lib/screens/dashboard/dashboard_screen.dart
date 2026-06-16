import 'dart:async';
import 'dart:ui' show ImageFilter;
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
import '../../models/subscription.dart';
import '../../models/catalog/catalog_models.dart';
import '../../services/catalog_service.dart';
import '../../config/catalog_merge.dart';
import '../../services/role_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard_ui_kit.dart';
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
import '../../widgets/kpi_carousel.dart';
import '../../widgets/business_types_bar.dart';
import '../../config/dashboard_modules.dart';
import '../../screens/capabilities/capabilities_registry.dart';
import '../../screens/capabilities/capability_scaffold.dart';
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

  // Estado de suscripción del tenant. Lo posee el Dashboard (no la
  // TrialBar) porque el header necesita saber si la barra del trial se
  // mostrará para dimensionar su alto y no dejar espacio vacío cuando el
  // tenant es Pro. Se inyecta a la TrialBar para evitar un segundo fetch.
  // `null` mientras carga / si falló → el header no reserva el espacio.
  SubscriptionStatus? _subscriptionStatus;

  // F041 — catálogo dinámico. Si está disponible, la grilla y el reel se
  // construyen desde él (reactivo a lo que configure el admin); si es null
  // (primer arranque sin red), se usa el bundle compilado (fallback).
  Catalog? _catalog;
  final _catalogService = CatalogService();

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncFromServer();
    _loadLowStockCount();
    _loadStoreStatus();
    _loadCapabilityFlags();
    _syncBusinessTypesFromServer();
    _loadSubscriptionStatus();
    _loadCatalog();

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

  /// Carga el estado de suscripción una sola vez para el header. Misma
  /// regla que la TrialBar (F009): si falla, NO se muestra la barra y el
  /// header queda compacto — no bloquea el Dashboard. El error se
  /// registra, nunca se traga en silencio.
  Future<void> _loadSubscriptionStatus() async {
    try {
      final api = ApiService(AuthService());
      final status = await api.fetchSubscriptionStatus();
      if (mounted) setState(() => _subscriptionStatus = status);
    } on AppError catch (e) {
      debugPrint('Dashboard: no se pudo cargar /subscription/status: '
          '${e.message}');
    } catch (e) {
      debugPrint('Dashboard: error inesperado al cargar suscripción: $e');
    }
  }

  /// Sincroniza los tipos de negocio desde el backend y refresca la barra.
  /// El login trae `business_type` (singular) pero NO el array
  /// `business_types`, así que la cache local quedaba vacía aunque el
  /// tenant tuviera varios tipos. Aquí leemos la fuente de verdad
  /// (`/store/profile`) y la persistimos sin tocar los feature flags.
  /// Offline-safe: si falla, se queda con lo que cargó _loadCapabilityFlags.
  Future<void> _syncBusinessTypesFromServer() async {
    try {
      final api = ApiService(AuthService());
      final profile = await api.fetchBusinessProfile();
      // Spec 051: el GET /store/profile SIEMPRE trae `feature_flags` + TODAS las
      // capacidades top-level (enable_recipes, enable_marketing_hub, enable_quotes,
      // …). Las refrescamos desde la fuente de verdad del servidor en CADA carga
      // del dashboard. Antes los flags solo se escribían al iniciar sesión: si el
      // login los omitía, o el caché del PWA servía el bundle viejo, o el usuario
      // solo recargaba (sesión restaurada de disco, sin re-login), una capacidad
      // ACTIVA (Recetas/menú) se quedaba atascada en "Descubre más opciones".
      // Refrescar aquí lo cura sin pedir re-login. Es SEGURO: el GET nunca llega
      // sin los flags, así que no los borra (a diferencia de un PATCH parcial).
      await AuthService().saveFeatureFlagsFromProfile(profile);
      final raw = profile['business_types'];
      if (raw is List) {
        final types = raw.whereType<String>().toList();
        await AuthService().setBusinessTypes(types);
        if (mounted) setState(() => _businessTypes = types);
      }
      // Releer los flags ya persistidos y repintar: mueve los módulos activos al
      // carrusel y los saca del reel "Descubre más opciones".
      if (mounted) await _loadCapabilityFlags();
    } catch (_) {
      // Offline / sin perfil — se conserva la cache local.
    }
  }

  /// Carga el catálogo dinámico: primero la cache (pinta al instante,
  /// offline-first) y luego refresca desde el backend. Si no hay nada
  /// (primer arranque sin red), el dashboard usa su bundle compilado.
  Future<void> _loadCatalog() async {
    final cached = await _catalogService.cached();
    if (cached != null && mounted) setState(() => _catalog = cached);
    final fresh = await _catalogService.refresh();
    if (fresh != null && mounted) setState(() => _catalog = fresh);
  }

  /// Acceso Pro = TRIAL activo o PRO_ACTIVE (igual criterio que PremiumAuth).
  bool get _isPro {
    final s = _subscriptionStatus?.status;
    return s == SubscriptionStatusValue.trial ||
        s == SubscriptionStatusValue.proActive;
  }

  /// Grilla + reel resueltos desde el catálogo dinámico, o null si aún no
  /// hay catálogo (entonces el dashboard usa el bundle compilado).
  CatalogDashboard? get _catalogDashboard {
    final c = _catalog;
    if (c == null || c.isEmpty) return null;
    return buildCatalogDashboard(
      c,
      businessTypes: _businessTypes,
      flags: _featureFlags,
      isPro: _isPro,
    );
  }

  /// Abre el editor de tipos de negocio y refresca al volver. Compartido
  /// por el chip del header y el botón "+" de la barra de tipos.
  Future<void> _openBusinessTypesEditor() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BusinessProfileScreen()),
    );
    if (mounted) {
      _loadCapabilityFlags();
      // Trae la verdad del backend por si el cache local no reflejó el
      // cambio (p.ej. la respuesta del PATCH no incluyó business_types).
      _syncBusinessTypesFromServer();
    }
  }

  /// Elimina un tipo de negocio (long-press de 2s en la barra). Persiste
  /// contra el backend (PATCH business_types) y refresca el estado local.
  /// Impide quedar sin ningún tipo: el perfil exige al menos uno.
  Future<void> _deleteBusinessType(String type) async {
    if (_businessTypes.length <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe conservar al menos un tipo de negocio.',
              style: TextStyle(fontSize: 15)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final updated = _businessTypes.where((t) => t != type).toList();
    // Optimista: refleja el cambio ya; si el backend falla, revertimos.
    setState(() => _businessTypes = updated);
    try {
      final api = ApiService(AuthService());
      await api.updateBusinessProfile({'business_types': updated});
      // Persistimos SOLO los tipos (no saveFeatureFlagsFromProfile, que
      // podría borrar los flags si la respuesta no los trae).
      await AuthService().setBusinessTypes(updated);
      if (mounted) _loadCapabilityFlags();
    } catch (e) {
      if (!mounted) return;
      // Revertimos a la verdad del backend.
      _syncBusinessTypesFromServer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el tipo: $e',
              style: const TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  /// Construye la lista de KPIs para el carrusel del Dashboard. Las
  /// fotos son Pexels (licencia libre, sin atribución obligatoria).
  /// "Ventas de hoy" se oculta para roles sin permiso de finanzas
  /// (un cajero no debe ver la facturación del día).
  List<KpiCardData> _buildKpiCards(BuildContext context) {
    final canSeeFinances = context.watch<RoleManager>().canSeeFinances;
    final cards = <KpiCardData>[];

    if (canSeeFinances) {
      cards.add(KpiCardData(
        title: 'Ventas de hoy',
        value: _formatCOP(_data.totalToday.round()),
        subtitle: _data.txCount > 0
            ? '${_data.txCount} venta${_data.txCount > 1 ? "s" : ""}'
            : 'primer día',
        photoUrl:
            'https://images.pexels.com/photos/3943723/pexels-photo-3943723.jpeg?auto=compress&cs=tinysrgb&w=900&h=700&fit=crop',
        fallbackIcon: Icons.trending_up_rounded,
        accentColor: const Color(0xFF3B82F6),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const FinancialDashboardScreen(),
        )),
      ));
    }

    cards.add(KpiCardData(
      title: 'Más vendido',
      value: _data.topProduct,
      photoUrl:
          'https://images.pexels.com/photos/4393668/pexels-photo-4393668.jpeg?auto=compress&cs=tinysrgb&w=900&h=700&fit=crop',
      fallbackIcon: Icons.star_rounded,
      accentColor: const Color(0xFFF59E0B),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ProductInsightsScreen(),
      )),
    ));

    cards.add(KpiCardData(
      title: 'Inventario',
      value: _data.prodCount == 0 ? 'Vacío' : '${_data.prodCount} ref.',
      photoUrl:
          'https://images.pexels.com/photos/4483610/pexels-photo-4483610.jpeg?auto=compress&cs=tinysrgb&w=900&h=700&fit=crop',
      fallbackIcon: Icons.inventory_2_rounded,
      accentColor: const Color(0xFF6366F1),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AddMerchandiseScreen(),
      )),
    ));

    return cards;
  }

  /// Capacidades opcionales ACTIVAS como cards del MISMO carrusel inmersivo
  /// que los KPIs (un solo carrusel — pedido del dueño). Usa la foto/acento
  /// del registry F040 y navega al módulo funcional. Reemplaza la sección
  /// "Sus capacidades activas" separada.
  List<KpiCardData> _buildActiveCapabilityCards(BuildContext context) {
    final cards = <KpiCardData>[];
    for (final m in dashboardModules) {
      if (m.layer != ModuleLayer.optional || m.capability == null) continue;
      if (!capabilityEnabled(m.capability, _featureFlags)) continue;
      final meta = capabilitiesRegistry[m.capability];
      cards.add(KpiCardData(
        title: m.title,
        value: 'Activo',
        subtitle: m.subtitle,
        photoUrl: meta?.heroPhotoUrl ?? '',
        fallbackIcon: m.icon,
        accentColor: m.color,
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => m.destination()),
          );
          if (mounted) _loadCapabilityFlags();
        },
        // Quitar del inicio: desactiva la capacidad → vuelve al reel
        // "Descubre más opciones". Solo si la capacidad tiene configKey.
        onRemove: meta == null ? null : () => _deactivateCapability(m, meta),
      ));
    }
    return cards;
  }

  /// Desactiva una capacidad opcional desde el carrusel (pedido del dueño:
  /// cada módulo activo debe poder apagarse y regresar al listado horizontal
  /// de "Descubre más opciones"). Pide confirmación, persiste el flag en
  /// `config.<configKey> = false` y refresca: al quedar el flag en false el
  /// módulo sale del carrusel/grilla y reaparece en el reel.
  Future<void> _deactivateCapability(
      DashboardModule m, CapabilityMetadata meta) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('¿Quitar ${m.title} del inicio?',
            style: const TextStyle(fontSize: 21)),
        content: const Text(
          'El módulo volverá a "Descubre más opciones" y podrá activarlo de '
          'nuevo cuando quiera. Sus datos no se borran.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Quitar', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final auth = AuthService();
      final api = ApiService(auth);
      final updated = await api.updateBusinessProfile({
        'config': {meta.configKey: false},
      });
      await auth.saveFeatureFlagsFromProfile(updated);
      if (mounted) await _loadCapabilityFlags();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${m.title} se quitó del inicio',
                style: const TextStyle(fontSize: 16)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo quitar: $e',
                style: const TextStyle(fontSize: 16)),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// IDs de capacidades opcionales activas — se muestran en el carrusel, así
  /// que se EXCLUYEN de la grilla para no duplicarlas (pedido del dueño).
  Set<String> _activeOptionalIds() => dashboardModules
      .where((m) =>
          m.layer == ModuleLayer.optional &&
          m.capability != null &&
          capabilityEnabled(m.capability, _featureFlags))
      .map((m) => m.id)
      .toSet();

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
      // Página BLANCA (estilo GitHub): los grupos gris claro (#F8F9FA)
      // se leen nítidos contra ella — antes ambos eran casi el mismo gris.
      backgroundColor: Colors.white,
      // El body se extiende DETRÁS de la barra inferior glass: así el
      // contenido se entrevé difuminado tras el botón al hacer scroll
      // (el spacer final del CustomScrollView evita que algo quede
      // permanentemente oculto).
      extendBody: true,
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
                  subscriptionStatus: _subscriptionStatus,
                  todayLabel: _todayLabel(),
                ),
              ),

              // ── Barra de tipos de negocio habilitados ──────────────
              // Justo bajo el header: chips ícono+texto por cada tipo,
              // "+" para agregar, y long-press 2s para quitar uno.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: BusinessTypesBar(
                    types: _businessTypes,
                    catalogTypes: _catalog?.types ?? const [],
                    onAdd: _openBusinessTypesEditor,
                    onDelete: _deleteBusinessType,
                  ),
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

              // ── KPI Carousel (F040 estilo inmersivo) ────────────
              // Reemplaza los 3 "glass cards" anteriores por un
              // carrusel con foto representativa + valor grande. El
              // primer KPI (Ventas de hoy) solo aparece para roles
              // con `canSeeFinances` (cajero no ve facturación).
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                  child: KpiCarousel(
                    // Un solo carrusel: KPIs + capacidades activas (Eventos,
                    // etc.). La sección "Sus capacidades activas" separada se
                    // eliminó; las activas se excluyen de la grilla abajo.
                    cards: [
                      ..._buildKpiCards(context),
                      ..._buildActiveCapabilityCards(context),
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
                                    const Text('Toque para ver pedidos sugeridos',
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
                    modules: _catalogDashboard?.reel ??
                        unactivatedOptionalModules(_featureFlags),
                    onReturned: _loadCapabilityFlags,
                  ),
                ),

                // F040/F042: las capacidades activas ya NO van en una sección
                // separada — se fusionaron en el carrusel de arriba (KPIs +
                // capacidades) y se excluyen de la grilla para no duplicarse.

                // ── F036: Grid adaptativo de módulos ────────────────
                // Reemplaza el antiguo stack imperativo de tarjetas
                // (Reporte, Clientes, Cotizaciones, Promociones,
                // Proveedores, Insumos, Recetas, Órdenes, Trabajos).
                // Las 4 categorías se construyen filtrando el registro
                // `dashboardModules` por el tipo de negocio + flags.
                SliverToBoxAdapter(
                  child: Builder(builder: (context) {
                    // Excluir capacidades activas (van en el carrusel) para
                    // que no aparezcan duplicadas en la grilla.
                    final activeIds = _activeOptionalIds();
                    final source = _catalogDashboard?.grid ??
                        visibleModulesFor(_businessType, _featureFlags);
                    final gridModules = source
                        .where((m) => !activeIds.contains(m.id))
                        .toList();
                    return DashboardModuleGrid(
                      businessType: _businessType,
                      flags: _featureFlags,
                      modules: gridModules,
                    );
                  }),
                ),

                // ── Recent Sales Header ─────────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 32, 24, 8),
                    child: Text('Últimas ventas',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937))),
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
                          // Mismo lenguaje que las listas agrupadas de
                          // módulos: tarjeta blanca, borde hairline,
                          // sombra suave y divisores clarísimos.
                          margin:
                              const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          decoration: DashUI.card(),
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            physics:
                                const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: _data.recentSales.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              thickness: 1,
                              indent: 76,
                              color: DashUI.divider,
                            ),
                            itemBuilder: (_, i) =>
                                _buildSaleTile(_data.recentSales[i]),
                          ),
                        ),
                ),

                // Spacer final: con `extendBody` el scroll pasa por detrás
                // de la barra glass — esta altura garantiza que "Últimas
                // ventas" pueda desplazarse por ENCIMA del botón y nunca
                // quede permanentemente oculto.
                const SliverToBoxAdapter(child: SizedBox(height: 104)),
              ],
            ),
          ),
        )),
        ],
      ),
      // ── Barra inferior glass (Glassmorphism funcional) ──────────────
      // Vidrio translúcido con blur: el contenido que queda detrás al
      // hacer scroll se difumina elegantemente en vez de cortarse contra
      // un fondo sólido. El botón es azul sólido de alto contraste, sin
      // bordes, esquinas 14.
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              // Vidrio de verdad: 0.62 de blanco — las "Últimas ventas"
              // se entrevén difuminadas (visibles pero ilegibles) detrás.
              color: Colors.white.withValues(alpha: 0.62),
              border: const Border(
                top: BorderSide(color: Color(0x0D000000), width: 1),
              ),
            ),
            child: SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
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
  /// Tipos de negocio del tenant. Ya NO se pintan en el header (viven en
  /// la BusinessTypesBar bajo el header); se conservan solo para que
  /// shouldRebuild repinte el header si cambian.
  final List<String> businessTypes;
  final String? branchName;
  final bool isStoreOpen;
  final bool loadingStoreStatus;
  final ValueChanged<bool> onToggleStore;
  final Future<void> Function() onLogout;
  final String todayLabel;
  /// Estado de suscripción del tenant (lo posee el Dashboard). Decide si
  /// la barra del trial se muestra; el header reserva su alto solo cuando
  /// realmente va a pintarse, evitando el espacio vacío que dejaba el
  /// alto fijo anterior cuando el tenant es Pro o aún carga.
  final SubscriptionStatus? subscriptionStatus;

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
    required this.todayLabel,
    this.subscriptionStatus,
  });

  // Alto del header = suma de los bloques que realmente se pintan, en
  // vez de un alto fijo. Antes era 234 const, que reservaba ~56dp para
  // la barra del trial aunque el tenant fuera Pro (barra = `SizedBox
  // .shrink`) y, con `MainAxisAlignment.center`, repartía el sobrante en
  // bandas vacías arriba y abajo. Resultado: header demasiado alto con
  // huecos. Ahora cada bloque aporta su alto solo si se muestra.
  //
  // _collapsedBody = 60 reserva el avatar de 40dp + 8 padding superior
  // + 16 padding inferior (estándar Material). Los valores llevan un
  // pequeño margen para no hacer overflow a 360dp (Art. I).
  static const double _vPadding = 24; // top 8 + bottom 16
  static const double _ownerLine = 26;
  static const double _businessLine = 20;
  static const double _branchLine = 16;
  static const double _detailGap = 8; // padding superior del bloque expandible
  static const double _storeRow = 42; // pill de estado + fecha
  static const double _trialGap = 10;
  static const double _trialBody = 74; // alto máx. de la barra/prompt del trial
  static const double _collapsedBody = 60;

  /// La barra del trial solo se pinta en TRIAL o FREE. En PRO (o mientras
  /// el estado carga / falló) no ocupa nada — y el header no la reserva.
  bool get _showsTrialBar {
    final s = subscriptionStatus;
    return s != null &&
        (s.status == SubscriptionStatusValue.trial ||
            s.status == SubscriptionStatusValue.free);
  }

  double get _expandedBody {
    var h = _vPadding +
        _ownerLine +
        _businessLine +
        _branchLine +
        _detailGap +
        _storeRow;
    if (_showsTrialBar) h += _trialGap + _trialBody;
    return h;
  }

  @override
  double get maxExtent => topPadding + _expandedBody;
  @override
  double get minExtent => topPadding + _collapsedBody;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final detailsOpacity = (1.0 - t * 1.8).clamp(0.0, 1.0);

    // ── Glassmorphism funcional ──────────────────────────────────────
    // Material translúcido en vez del gradiente sólido y abrupto: en
    // reposo (t=0) el tinte azul ya es levemente translúcido (0.94) y al
    // desplazar (t→1) baja a 0.68 + blur — el contenido se entrevé
    // sutilmente detrás del vidrio, pero el TINTE azul garantiza que el
    // texto blanco (nombre, "Abierta", fecha) conserve contraste absoluto.
    // El blur cuesta en Android de gama baja (Art. I), así que el
    // BackdropFilter solo se monta cuando ya hay scroll.
    // Glass PRONUNCIADO: al hacer scroll el carrusel pasa por debajo y se
    // difumina con claridad tras el vidrio azul (0.60 de tinte + blur 18).
    // El tinte azul mantiene el texto blanco nítido (contraste absoluto).
    final bgAlpha = 0.92 - 0.32 * t; // 0.92 → 0.60
    final blurSigma = 18.0 * t; // 0 → 18
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF1E3A8A).withValues(alpha: bgAlpha),
        const Color(0xFF3B82F6).withValues(alpha: bgAlpha),
        const Color(0xFF6366F1).withValues(alpha: bgAlpha),
      ],
    );

    Widget surface = Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        // Sombra amplia y muy difuminada — separa el vidrio del contenido
        // sin la sombra dura anterior.
        boxShadow: t > 0.3
            ? [
                BoxShadow(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
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
            // El contenido se ancla arriba; el alto del header ya se
            // ajusta a lo que se pinta, así que no queda sobrante que
            // `center` repartiría en bandas vacías arriba/abajo.
            mainAxisAlignment: MainAxisAlignment.start,
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
                                // Los tipos de negocio ya NO se muestran aquí:
                                // viven en la BusinessTypesBar bajo el header,
                                // con agregar (+) y borrar (long-press).
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
                          // Acceso directo a la vista de planes. Solo se
                          // monta en TRIAL/FREE; el alto del header ya
                          // reservó su espacio (ver `_showsTrialBar`). En
                          // PRO no se incluye → cero espacio vacío. El
                          // estado se inyecta desde el Dashboard para no
                          // hacer un segundo fetch (`selfLoad: false`).
                          if (_showsTrialBar) ...[
                            const SizedBox(height: 10),
                            TrialBar(
                              status: subscriptionStatus,
                              selfLoad: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

    // El BackdropFilter solo se monta cuando hay desplazamiento real:
    // en reposo (sigma 0) ahorramos el `saveLayer` que el blur exige —
    // crítico en Android de gama baja.
    if (blurSigma > 0.5) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: surface,
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
      o.subscriptionStatus?.status != subscriptionStatus?.status ||
      o.subscriptionStatus?.trialDaysRemaining !=
          subscriptionStatus?.trialDaysRemaining ||
      !_listEquals(o.businessTypes, businessTypes);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// _GlassCard removido — los 3 KPIs ahora usan KpiCarousel (F040).

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
