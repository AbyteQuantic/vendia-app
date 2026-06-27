import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'database/collections/local_catalog_product.dart';
import 'database/database_service.dart';
import 'database/sync/connectivity_monitor.dart';
import 'database/sync/sales_sync.dart';
import 'database/sync/sync_service.dart';
import 'services/active_fiado_service.dart';
import 'services/api_service.dart';
import 'services/seasonal_branding_controller.dart';
import 'services/seasonal_branding_service.dart';
import 'services/auth_service.dart';
import 'services/task_center_controller.dart';
import 'services/backend_warmup.dart';
import 'services/push_service.dart';
import 'services/hardware_service.dart';
import 'services/tax_settings_service.dart';
import 'models/branch.dart';
import 'services/branch_provider.dart';
import 'services/notification_toast_controller.dart';
import 'services/role_manager.dart';
import 'theme/app_theme.dart';
import 'screens/splash/animated_splash_screen.dart';
import 'utils/notification_navigation.dart';
import 'utils/notification_router.dart';
import 'widgets/draggable_toast_host.dart';
import 'widgets/premium_upsell_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env').catchError((_) {});

  await DatabaseService.instance.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Spec 012 (FR-03) — wake the backend early. Render's free tier
  // sleeps after ~15 min idle; firing this fire-and-forget ping before
  // the merchant's first action lets the ~50 s cold start overlap with
  // the splash + login instead of stalling that first call. Not
  // awaited: a sleeping backend makes this request slow, and nothing
  // in the UI may wait on it.
  BackendWarmup.ping();

  // Spec 038 — init de Push Notifications (FCM Web + Android).
  // Es fire-and-forget: si Firebase no responde (red caída, browser
  // que bloquea SW, iPhone sin PWA), degrada en silencio sin
  // bloquear el arranque. NUNCA pide permiso al usuario acá —
  // eso lo hace PushOptinCard cuando el tendero toca el botón.
  // Spec 056 slice 3 — al tocar una push, abrir el módulo correcto con
  // el dato precargado, reusando el router de notificaciones. Navega por
  // la key global porque el handler corre fuera de un BuildContext.
  unawaited(PushService().init(onDeepLink: _handlePushDeepLink));

  runApp(const VendIAApp());
}

/// Resuelve el `deep_link` de una push y navega al destino. Silencioso
/// si el path no mapea a un módulo conocido o el navigator no está listo.
void _handlePushDeepLink(String deepLink) {
  final dest = destinationForPath(deepLink);
  final builder = notificationRouteBuilder(dest);
  if (builder == null) return;
  PremiumUpsellController.navigatorKey.currentState
      ?.push(MaterialPageRoute(builder: builder));
}

class VendIAApp extends StatefulWidget {
  const VendIAApp({super.key});

  @override
  State<VendIAApp> createState() => _VendIAAppState();
}

class _VendIAAppState extends State<VendIAApp> {
  late final ConnectivityMonitor _connectivityMonitor;
  late final SyncService _syncService;
  late final RoleManager _roleManager;
  late final ActiveFiadoService _activeFiado;
  // BranchProvider lives at the root so BranchesListScreen,
  // EmployeesScreen, MainDashboardScreen header chip, etc. all share
  // one source of truth for the active sede. Not having it here made
  // BranchesListScreen crash with ProviderNotFoundException the
  // second the tendero tapped "Mis Sucursales".
  late final BranchProvider _branchProvider;
  // Spec 086 — branding estacional (server-driven). Se siembra de cache al
  // arranque (acento en cold-start) y se revalida en segundo plano.
  final SeasonalBrandingController _seasonal = SeasonalBrandingController();

  @override
  void initState() {
    super.initState();
    _loadBranding();
    _connectivityMonitor = ConnectivityMonitor();
    _syncService = SyncService(
      db: DatabaseService.instance,
      connectivity: _connectivityMonitor,
      auth: AuthService(),
    );
    _roleManager = RoleManager(AuthService());
    _roleManager.refresh();
    _activeFiado = ActiveFiadoService();
    _branchProvider = BranchProvider();
    _syncService.startBackgroundSync();
    _syncCatalogInBackground();
    _syncSalesOnStart();
    _loadBranches();
    _bootstrapHardware();
    _bootstrapTaxSettings();
  }

  /// Hydrate the TaxSettingsService from SharedPreferences. We defer
  /// this to addPostFrameCallback so a slow disk read never blocks the
  /// first POS frame — the snapshotForLine() call sites tolerate the
  /// pre-load state (returns the safe "VAT off" snapshot) until the
  /// real prefs land.
  void _bootstrapTaxSettings() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // loadFromPrefs() already swallows its own errors.
      TaxSettingsService.instance.loadFromPrefs();
    });
  }

  /// Hydrate the HardwareService from SharedPreferences and, if the
  /// master switch was ON in a previous session, kick off an
  /// auto-reconnect after the first frame so the cashier can ring up
  /// the very first sale of the day with a working printer.
  void _bootstrapHardware() {
    final hw = HardwareService.instance;
    // loadFromPrefs() is fire-and-forget: a prefs failure must not
    // block startup. The auto-reconnect runs after the first frame to
    // avoid contending with the splash screen / DB init.
    () async {
      await hw.loadFromPrefs();
      if (hw.isEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // tryReconnect already swallows its own errors.
          hw.tryReconnect();
        });
      }
    }();
  }

  /// Sync sales bidirectionally: pull from server + push unsynced local sales.
  Future<void> _syncSalesOnStart() async {
    // Only sync if user has an active session
    final hasSession = await AuthService().hasSession();
    if (!hasSession) return;
    await SalesSyncService.fullSync();
  }

  /// Load branches into BranchProvider so the dashboard shows the branch name.
  Future<void> _loadBranches() async {
    try {
      final auth = AuthService();
      final hasSession = await auth.hasSession();
      if (!hasSession) return;
      final api = ApiService(auth);
      final raw = await api.fetchBranches();
      final branches = raw.map((json) => Branch.fromJson(json)).toList();
      _branchProvider.setBranches(branches);
      // Select the branch from the saved session (employee's assigned branch)
      final savedBranchId = await auth.getBranchId();
      if (savedBranchId != null && savedBranchId.isNotEmpty) {
        _branchProvider.selectBranchById(savedBranchId);
      }
    } catch (e) {
      debugPrint('[BRANCHES] load failed: $e');
    }
  }

  /// Sync the OFF catalog to Isar in background for offline-first autocomplete.
  Future<void> _syncCatalogInBackground() async {
    try {
      // Race con AuthService cargando el token desde disco al arranque
      // (mismo gate que `_syncSalesOnStart` y `_loadBranches`). Sin el
      // chequeo, el primer call sale sin Authorization → 401 → cascada
      // de Uncaught Errors visibles en consola en cada arranque.
      final auth = AuthService();
      if (!await auth.hasSession()) return;
      final api = ApiService(auth);
      final items = await api.fetchCatalogSync();
      final products = items
          .map((json) => LocalCatalogProduct.fromJson(json))
          .toList();
      await DatabaseService.instance.syncCatalog(products);
      debugPrint('[CATALOG] synced ${products.length} products to Isar');
    } catch (e) {
      debugPrint('[CATALOG] sync failed (will retry next launch): $e');
    }
  }

  // Spec 086 — siembra el branding cacheado (aplica el acento en cold-start) y
  // luego revalida con el servidor (fail-safe: si falla, queda la marca normal).
  Future<void> _loadBranding() async {
    _seasonal.seed(await SeasonalBrandingService().cached());
    if (mounted) setState(() {});
    await _seasonal.refresh();
  }

  @override
  void dispose() {
    _syncService.dispose();
    _connectivityMonitor.dispose();
    _branchProvider.dispose();
    _seasonal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _connectivityMonitor),
        ChangeNotifierProvider.value(value: _syncService),
        ChangeNotifierProvider.value(value: _roleManager),
        ChangeNotifierProvider.value(value: _activeFiado),
        ChangeNotifierProvider.value(value: _branchProvider),
        ChangeNotifierProvider(create: (_) => NotificationToastController()),
        // Spec 078 — Centro de Tareas unificado: poller único app-wide.
        ChangeNotifierProvider(create: (_) => TaskCenterController(ApiService(AuthService()))),
        // Spec 086 — branding estacional disponible app-wide (banner/saludo).
        ChangeNotifierProvider.value(value: _seasonal),
      ],
      child: MaterialApp(
        title: 'VendIA',
        debugShowCheckedModeBanner: false,
        navigatorKey: PremiumUpsellController.navigatorKey,
        scaffoldMessengerKey: ApiService.scaffoldKey,
        // Acento estacional en cold-start (desde cache sembrada); sin override
        // → acento de marca. Re-temar en vivo se evita (parpadeo); banner/saludo
        // sí refrescan en vivo via Consumer del controller.
        theme: AppTheme.lightWith(accentOverride: _seasonal.activeAccent),
        // Force light mode — dark mode not yet supported for Gerontodiseño
        themeMode: ThemeMode.light,
        // Disable overscroll glow/stretch globally (fixes teal circles on Android 12+)
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          overscroll: false,
        ),
        // Toast global de notificaciones, sobre cualquier pantalla. Vive
        // hasta que el usuario lo cierra (Spec 056 slice 2).
        builder: (context, child) {
          return Stack(
            children: [
              if (child != null) child,
              // Toast arrastrable (Spec 056/078): el usuario lo mueve para que no
              // le tape la información; por default arriba bajo la barra de estado.
              const DraggableToastHost(),
            ],
          );
        },
        home: const AnimatedSplashScreen(),
      ),
    );
  }
}
