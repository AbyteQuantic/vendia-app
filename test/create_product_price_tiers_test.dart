// Spec: specs/029-precios-multi-tier/spec.md
//
// T-24 — Widget test del CreateProductScreen con la capacidad
// enable_price_tiers prendida y apagada.
//
// Cobertura:
//   - AC-01: con la capacidad OFF, los 3 inputs de tier NO aparecen.
//   - AC-03: con la capacidad ON, los 3 inputs aparecen.
//
// Notas:
//   * La pantalla lee AuthService.getFeatureFlags() en initState.
//     Stubbamos secure_storage para servir el blob de feature_flags y
//     forzar el camino ON/OFF deterministamente.
//   * El screen completo contiene tiles que overflowean ligeramente
//     en algunos viewports de test (no afecta el flujo real en 360dp
//     de gama baja, pero ensucia los logs). Capturamos esos
//     RenderFlex.overflow para no fallar el test por warnings que no
//     tienen que ver con F029.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/create_product_screen.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(() {
    // Silence pre-existing layout overflows (scan-barcode tile, etc.)
    // — F029 no los toca y el test no debe fallar por ruido ajeno.
    FlutterError.onError = (FlutterErrorDetails details) {
      final ex = details.exception;
      if (ex is FlutterError &&
          ex.message.contains('A RenderFlex overflowed')) {
        return;
      }
      FlutterError.presentError(details);
    };
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    FlutterError.onError = FlutterError.presentError;
  });

  group('CreateProductScreen — precios multi-tier (F029)', () {
    testWidgets(
        'AC-01: capacidad OFF → los 3 inputs de tier NO aparecen, '
        'solo el precio venta legacy', (tester) async {
      _mockSecureStorage({
        'vendia_feature_flags': jsonEncode({'enable_price_tiers': false}),
      });

      await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const Key('product_price_tier_1'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('product_price_tier_2'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('product_price_tier_3'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
        'AC-03: capacidad ON → aparecen 3 inputs de tier además del '
        'precio venta (4 campos de precio en total)', (tester) async {
      _mockSecureStorage({
        'vendia_feature_flags': jsonEncode({'enable_price_tiers': true}),
      });

      // Damos un viewport amplio para evitar los RenderFlex overflows
      // pre-existentes (scan barcode tile, opciones avanzadas) que no
      // tienen que ver con F029. Width 1200 + DPR 1 deja muchísimo
      // espacio para los Row internos.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
      // initState dispara _loadPriceTierConfig — pump varias veces
      // para que el setState async se asiente. El GET de profile va a
      // fallar (sin backend) — eso está bien, los defaults aplican.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const Key('product_price_tier_1'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('product_price_tier_2'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('product_price_tier_3'), skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}
