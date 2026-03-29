import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'database/database_service.dart';
import 'database/sync/connectivity_monitor.dart';
import 'database/sync/sync_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash/animated_splash_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _connectivityMonitor = ConnectivityMonitor();
    _syncService = SyncService(
      db: DatabaseService.instance,
      connectivity: _connectivityMonitor,
      auth: AuthService(),
    );
    _syncService.startBackgroundSync();
  }

  @override
  void dispose() {
    _syncService.dispose();
    _connectivityMonitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _connectivityMonitor),
        ChangeNotifierProvider.value(value: _syncService),
      ],
      child: MaterialApp(
        title: 'VendIA',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: ApiService.scaffoldKey,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const AnimatedSplashScreen(),
      ),
    );
  }
}
