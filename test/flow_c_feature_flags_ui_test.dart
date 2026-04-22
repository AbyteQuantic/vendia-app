import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vendia_pos/screens/dashboard/main_dashboard_screen.dart';
import 'package:vendia_pos/screens/pos/pos_screen.dart' show ServiceChargeButton;
import 'package:vendia_pos/services/auth_service.dart';

/// Flow C — Smart Feature Flags UI (tenant = reparacion_muebles)
///
/// Certifies two related invariants tied to migration 021:
///   1. MESAS never appears for a tenant whose feature_flags disable
///      `enable_tables` (reparación de muebles is retail-adjacent;
///      tables would be a cognitive-friction violation).
///   2. The Cobrar Servicio button is renderable with the expected
///      key when the tenant has `enable_services=true`.
///
/// The two assertions live in the same file so a future refactor that
/// swaps the flag source has a single place to update.
///
/// Storage is seeded via the flutter_secure_storage method channel so
/// AuthService can decode a real feature_flags blob; SharedPreferences
/// uses the plugin's official test hook.

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Stubbed secure storage — only `read` / `readAll` are needed by the
/// dashboard's feature-flag loader. Writes are no-op (tests only seed
/// values up front).
void _mockSecureStorage(Map<String, String?> seed) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'read':
        final args = (call.arguments as Map).cast<String, Object?>();
        return seed[args['key']];
      case 'readAll':
        return seed;
      case 'containsKey':
        final args = (call.arguments as Map).cast<String, Object?>();
        return seed.containsKey(args['key']);
      default:
        // write / delete / deleteAll — tests don't care, swallow
        return null;
    }
  });
}

/// reparacion_muebles feature flags per `models.DefaultFeatureFlags`:
/// enable_services=true, enable_custom_billing=true, everything else
/// false.
Map<String, dynamic> get _reparacionMueblesFlags => {
      'enable_tables': false,
      'enable_kds': false,
      'enable_tips': false,
      'enable_services': true,
      'enable_custom_billing': true,
      'enable_fractional_units': false,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('Flow C — Smart Feature Flags UI (reparacion_muebles)', () {
    setUp(() {
      // Seed feature flags into secure storage so
      // AuthService.getFeatureFlags() decodes the right shape.
      _mockSecureStorage({
        'vendia_feature_flags': jsonEncode(_reparacionMueblesFlags),
        'vendia_business_types': jsonEncode(['reparacion_muebles']),
        // charge_mode defaults to pre_payment (retail). No need to set,
        // but include so the dashboard reads a deterministic value.
        'vendia_charge_mode': 'pre_payment',
      });

      // SharedPreferences is read by the dashboard's _loadChargeMode().
      // Keep it aligned with the feature flags so both render paths
      // agree (isPostPayment stays false).
      SharedPreferences.setMockInitialValues({
        'vendia_charge_mode': 'pre_payment',
      });
    });

    testWidgets(
        'el widget de Gestión de Mesas (btn_mesas) NO existe en el árbol',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainDashboardScreen()));
      await tester.pump(); // initState → _loadFeatureFlags runs
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('btn_mesas')), findsNothing,
          reason: 'enable_tables=false para reparacion_muebles — sin mesas');
      expect(find.text('MESAS'), findsNothing);
    });

    testWidgets('el botón VENDER sí aparece (flujo retail/service para POS)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainDashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('btn_vender')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('btn_vender')),
          matching: find.text('VENDER'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'KDS bell (notificaciones) está oculto cuando enable_kds=false',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainDashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // La campana de KDS sólo se renderiza para bar/restaurante. Para
      // reparacion_muebles debe estar oculta.
      expect(find.byIcon(Icons.notifications_rounded), findsNothing);
    });

    testWidgets(
        'AuthService reporta enable_services=true → prerrequisito del botón Cobrar Servicio',
        (tester) async {
      // La etapa 1 del contrato: el tenant tiene la flag activada.
      final flags = await AuthService().getFeatureFlags();

      expect(flags.enableServices, isTrue,
          reason: 'Prerrequisito para mostrar Cobrar Servicio');
      expect(flags.enableTables, isFalse);
      expect(flags.enableKDS, isFalse);
      expect(flags.enableCustomBilling, isTrue);
    });

    testWidgets(
        'el widget Cobrar Servicio sí existe (findsOneWidget) y usa la key contractual',
        (tester) async {
      // Etapa 2 del contrato: dado el prerrequisito, el widget renderiza
      // con la key `btn_cobrar_servicio`. Se monta aislado del PosScreen
      // completo porque el árbol completo arrastra dependencias HTTP/Isar
      // irrelevantes al assert.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceChargeButton(onPressed: () {}),
          ),
        ),
      );

      expect(find.byKey(const Key('btn_cobrar_servicio')), findsOneWidget);
      expect(
        find.textContaining('Cobrar Servicio'),
        findsOneWidget,
        reason: 'La etiqueta debe mencionar el servicio explícitamente',
      );
    });
  });
}
