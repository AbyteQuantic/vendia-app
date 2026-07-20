// Spec: specs/107-dashboard-v2-resumen/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vendia_pos/screens/home/home_screen.dart';
import 'package:vendia_pos/screens/home/home_widgets.dart';
import 'package:vendia_pos/services/home_summary_service.dart';

Map<String, dynamic> _summaryJson({int sales = 486500, int online = 1}) => {
      'sales_today': {'total': sales, 'count': 12},
      'profit_today': {'amount': 132400, 'margin_pct': 27},
      'cash_shift': {'open': true},
      'receivables': {'total': 184000, 'debtors': 7, 'oldest_days': 12},
      'in_progress': {'tables': 2, 'kitchen': 1, 'online': online},
      'low_stock': {
        'count': 5,
        'examples': ['Arroz', 'Aceite']
      },
      'movements': [
        {
          'kind': 'sale',
          'title': 'Venta — efectivo',
          'amount': 38500,
          'sign': 1,
          'status': 'Pagada',
          'at': DateTime.now().toIso8601String(),
        }
      ],
      'tasks': {'urgent': 1, 'actionable': 3},
      'generated_at': DateTime.now().toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HomeSummaryService (T-10, AC-10)', () {
    test('red OK → fresco y cachea', () async {
      final svc = HomeSummaryService(fetch: () async => _summaryJson());
      final s = await svc.load();
      expect(s.fromCache, isFalse);
      expect(s.salesTotal, 486500);
      expect(s.receivablesDebtors, 7);
    });

    test('red falla → cae al caché con antigüedad; sin caché → vacío', () async {
      final ok = HomeSummaryService(fetch: () async => _summaryJson());
      await ok.load(); // siembra caché
      final broken =
          HomeSummaryService(fetch: () async => throw Exception('offline'));
      final s = await broken.load();
      expect(s.fromCache, isTrue);
      expect(s.salesTotal, 486500);

      SharedPreferences.setMockInitialValues({});
      final s2 = await broken.load();
      expect(s2.isEmpty, isTrue, reason: 'sin caché → vacío, nunca lanza');
    });
  });

  group('buildLiveCards (T-14, AC-05/06)', () {
    HomeSummary s([Map<String, dynamic>? raw]) => HomeSummary(
        raw: raw ?? _summaryJson(), fromCache: false, ageMinutes: 0);
    void noop() {}

    test('con operación: cuentas por cobrar, ganancia, en curso, stock', () {
      final cards = buildLiveCards(
          s: s(),
          hasOperation: true,
          onFiados: noop,
          onGanancias: noop,
          onOperacion: noop,
          onInventario: noop,
          onHistorial: noop);
      expect(cards.map((c) => c.key),
          ['receivables', 'profit', 'in_progress', 'low_stock']);
      expect(cards[0].value, r'$ 184.000');
      expect(cards[0].subtitle, contains('7 clientes'));
      expect(cards[0].subtitle, contains('12 días'));
    });

    test('sin operación: "En curso" no aparece y entra la de ventas (AC-06)',
        () {
      final cards = buildLiveCards(
          s: s(),
          hasOperation: false,
          onFiados: noop,
          onGanancias: noop,
          onOperacion: noop,
          onInventario: noop,
          onHistorial: noop);
      expect(cards.map((c) => c.key),
          ['receivables', 'profit', 'low_stock', 'sales_count']);
    });

    test('tenant sin datos: estados vacíos amables (spec §9)', () {
      final cards = buildLiveCards(
          s: HomeSummary(raw: const {}, fromCache: false, ageMinutes: 0),
          hasOperation: false,
          onFiados: noop,
          onGanancias: noop,
          onOperacion: noop,
          onInventario: noop,
          onHistorial: noop);
      expect(cards[0].value, 'Al día');
      expect(cards[1].subtitle, contains('Aún no hay ventas'));
    });
  });

  group('HomeScreenV2 (T-16, AC-01/02)', () {
    testWidgets('360dp sin overflow, una llamada, ventas y FAB visibles',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var calls = 0;
      final svc = HomeSummaryService(
          persist: false,
          fetch: () async {
            calls++;
            return _summaryJson();
          });
      await tester.pumpWidget(MaterialApp(
        home: HomeScreenV2(
          ownerName: 'Carmen',
          businessName: 'La Esquina',
          summaryServiceOverride: svc,
          capabilitiesOverride: const {'tables'},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(calls, 1, reason: 'FR-01: una sola llamada al montar');
      expect(find.byKey(const Key('home_sales_today')), findsOneWidget);
      expect(find.textContaining('486.500'), findsOneWidget);
      expect(find.byKey(const Key('vendi_fab')), findsOneWidget);
      expect(find.byKey(const Key('live_card_receivables')), findsOneWidget);
      expect(find.byKey(const Key('hero_carousel')), findsOneWidget);
      expect(find.byKey(const Key('home_all_modules')), findsOneWidget);
    });

    testWidgets('resumen desde caché muestra el aviso de antigüedad (AC-10)',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ok = HomeSummaryService(fetch: () async => _summaryJson());
      await ok.load();
      final broken =
          HomeSummaryService(fetch: () async => throw Exception('offline'));
      await tester.pumpWidget(MaterialApp(
        home: HomeScreenV2(
          ownerName: 'C',
          businessName: 'B',
          summaryServiceOverride: broken,
          capabilitiesOverride: const {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('home_cache_notice')), findsOneWidget);
    });
  });
}
