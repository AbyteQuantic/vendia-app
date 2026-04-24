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
import 'services/auth_service.dart';
import 'services/branch_provider.dart';
import 'services/role_manager.dart';
import 'theme/app_theme.dart';
import 'screens/splash/animated_splash_screen.dart';
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
  runApp(const VendIAApp());
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

  @override
  void initState() {
    super.initState();
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
  }

  /// Sync sales bidirectionally: pull from server + push unsynced local sales.
  Future<void> _syncSalesOnStart() async {
    // Only sync if user has an active session
    final hasSession = await AuthService().hasSession();
    if (!hasSession) return;
    await SalesSyncService.fullSync();
  }

  /// Sync the OFF catalog to Isar in background for offline-first autocomplete.
  Future<void> _syncCatalogInBackground() async {
    try {
      final api = ApiService(AuthService());
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

  @override
  void dispose() {
    _syncService.dispose();
    _connectivityMonitor.dispose();
    _branchProvider.dispose();
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
      ],
      child: MaterialApp(
        title: 'VendIA',
        debugShowCheckedModeBanner: false,
        navigatorKey: PremiumUpsellController.navigatorKey,
        scaffoldMessengerKey: ApiService.scaffoldKey,
        theme: AppTheme.light,
        // Force light mode — dark mode not yet supported for Gerontodiseño
        themeMode: ThemeMode.light,
        // Disable overscroll glow/stretch globally (fixes teal circles on Android 12+)
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          overscroll: false,
        ),
        home: const AnimatedSplashScreen(),
      ),
    );
  }
}
