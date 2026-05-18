// Spec: specs/008-planes-suscripcion-epayco/spec.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/subscription.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/premium_upsell_sheet.dart';

/// Widget tests for the soft paywall / plan catalog sheet (Feature 008).
/// Coverage:
///   - The sheet loads the plan catalog and renders Gratis + Pro cards
///     with the CTA + dismiss button.
///   - Picking the "Pro" CTA calls `createCheckout`, opens the ePayco
///     URL, and refreshes the subscription status afterwards.
///   - A checkout error surfaces inline (no swallowed errors).
///   - PremiumUpsellController.notifyBlocked() routes into the
///     showOverride when present and is idempotent.

/// Fake ApiService: each test controls the three Feature 008 calls.
/// Overriding only the subscription methods keeps the double minimal —
/// the sheet touches nothing else during its lifecycle.
class _FakeApi extends ApiService {
  _FakeApi({
    this.onPlans,
    this.onStatus,
    this.onCheckout,
  }) : super(AuthService());

  final Future<List<SubscriptionPlan>> Function()? onPlans;
  final Future<SubscriptionStatus> Function()? onStatus;
  final Future<CheckoutSession> Function(String plan, String interval)?
      onCheckout;

  int checkoutCalls = 0;
  int statusCalls = 0;
  String? lastCheckoutPlan;
  String? lastCheckoutInterval;

  @override
  Future<List<SubscriptionPlan>> fetchPlans() {
    if (onPlans == null) return Future.value(_defaultPlans());
    return onPlans!();
  }

  @override
  Future<SubscriptionStatus> fetchSubscriptionStatus() {
    statusCalls += 1;
    if (onStatus == null) {
      return Future.value(const SubscriptionStatus(
        status: SubscriptionStatusValue.free,
        plan: PlanId.gratis,
      ));
    }
    return onStatus!();
  }

  @override
  Future<CheckoutSession> createCheckout({
    required String plan,
    required String interval,
  }) {
    checkoutCalls += 1;
    lastCheckoutPlan = plan;
    lastCheckoutInterval = interval;
    if (onCheckout == null) {
      return Future.value(CheckoutSession(
        reference: 'ref-test',
        checkoutUrl: 'https://checkout.epayco.co/test',
        amount: 29900,
        description: 'VendIA Pro',
        plan: plan,
        interval: interval,
      ));
    }
    return onCheckout!(plan, interval);
  }
}

List<SubscriptionPlan> _defaultPlans() => const [
      SubscriptionPlan(
        id: PlanId.gratis,
        name: 'Gratis',
        description: 'Lo esencial para vender',
        prices: [PlanPrice(interval: BillingInterval.mensual, amount: 0)],
        features: ['Registrar ventas'],
      ),
      SubscriptionPlan(
        id: PlanId.pro,
        name: 'Pro',
        description: 'Todas las herramientas',
        prices: [
          PlanPrice(interval: BillingInterval.mensual, amount: 29900),
          PlanPrice(interval: BillingInterval.anual, amount: 299000),
        ],
        features: ['Reportes', 'Fiar a clientes'],
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(() {
    PremiumUpsellController.resetForTest();
  });

  tearDown(() {
    PremiumUpsellController.showOverride = null;
    PremiumUpsellController.resetForTest();
  });

  /// Pumps a button that opens the sheet with the supplied fakes.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required _FakeApi api,
    CheckoutLauncher? launcher,
    String? reason,
  }) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPremiumUpsellSheet(
                context,
                reason: reason,
                api: api,
                launcher: launcher,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('loads catalog and renders Gratis + Pro cards + CTA',
      (tester) async {
    await pumpSheet(tester, api: _FakeApi(), reason: 'Tu prueba terminó');

    expect(find.byKey(const Key('premium_upsell_sheet')), findsOneWidget);
    expect(find.byKey(const Key('plan_card_gratis')), findsOneWidget);
    expect(find.byKey(const Key('plan_card_pro')), findsOneWidget);
    expect(find.byKey(const Key('premium_upsell_cta')), findsOneWidget);
    expect(find.byKey(const Key('premium_upsell_dismiss')), findsOneWidget);
    expect(find.textContaining('Tu prueba terminó'), findsWidgets);
    // Monthly price is shown in COP format.
    expect(find.textContaining('29.900'), findsWidgets);
  });

  testWidgets('dismiss CTA closes the sheet without side effects',
      (tester) async {
    final api = _FakeApi();
    await pumpSheet(tester, api: api);

    expect(find.byKey(const Key('premium_upsell_sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('premium_upsell_dismiss')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('premium_upsell_sheet')), findsNothing);
    expect(api.checkoutCalls, equals(0));
  });

  testWidgets('Pro CTA calls createCheckout, opens ePayco, refreshes status',
      (tester) async {
    Uri? launchedUrl;
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.proActive,
        plan: PlanId.pro,
        interval: BillingInterval.mensual,
      ),
    );

    await pumpSheet(
      tester,
      api: api,
      launcher: (url) async {
        launchedUrl = url;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('premium_upsell_cta')));
    await tester.pumpAndSettle();

    expect(api.checkoutCalls, equals(1));
    expect(api.lastCheckoutPlan, equals(PlanId.pro));
    expect(api.lastCheckoutInterval, equals(BillingInterval.mensual));
    expect(launchedUrl.toString(),
        equals('https://checkout.epayco.co/test'));
    // The status is re-fetched after returning from the checkout so
    // the UI reflects the webhook-driven promotion.
    expect(api.statusCalls, greaterThanOrEqualTo(1));
    // Promotion confirmed → sheet closes.
    expect(find.byKey(const Key('premium_upsell_sheet')), findsNothing);
  });

  testWidgets('annual interval is forwarded to createCheckout',
      (tester) async {
    final api = _FakeApi();
    await pumpSheet(
      tester,
      api: api,
      launcher: (_) async => true,
    );

    await tester.tap(find.byKey(const Key('interval_anual')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('premium_upsell_cta')));
    await tester.pumpAndSettle();

    expect(api.lastCheckoutInterval, equals(BillingInterval.anual));
  });

  testWidgets('checkout failure surfaces an inline error (no swallow)',
      (tester) async {
    final api = _FakeApi(
      onCheckout: (_, __) async => throw const AppError(
        type: AppErrorType.server,
        message: 'No pudimos generar el pago.',
      ),
    );

    await pumpSheet(
      tester,
      api: api,
      launcher: (_) async => true,
    );

    await tester.tap(find.byKey(const Key('premium_upsell_cta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('premium_upsell_checkout_error')),
        findsOneWidget);
    expect(find.text('No pudimos generar el pago.'), findsOneWidget);
    // Sheet stays open so the user can retry.
    expect(find.byKey(const Key('premium_upsell_sheet')), findsOneWidget);
  });

  testWidgets('catalog load failure shows retry control', (tester) async {
    final api = _FakeApi(
      onPlans: () async => throw const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión.',
      ),
    );

    await pumpSheet(tester, api: api);

    expect(find.byKey(const Key('premium_upsell_load_error')),
        findsOneWidget);
    expect(find.byKey(const Key('premium_upsell_retry')), findsOneWidget);
  });

  testWidgets(
      'PremiumUpsellController.notifyBlocked fires the override exactly once',
      (tester) async {
    int calls = 0;
    String? lastReason;
    final completer = Completer<void>();

    PremiumUpsellController.showOverride = (ctx, reason) async {
      calls += 1;
      lastReason = reason;
      await completer.future;
    };

    await tester.pumpWidget(MaterialApp(
      navigatorKey: PremiumUpsellController.navigatorKey,
      home: const Scaffold(body: Text('ready')),
    ));

    final f1 = PremiumUpsellController.notifyBlocked(reason: 'expired');
    final f2 = PremiumUpsellController.notifyBlocked(reason: 'expired');

    await f2;
    expect(calls, equals(1));
    expect(lastReason, equals('expired'));

    completer.complete();
    await f1;

    expect(calls, equals(1),
        reason: 'A burst of 403s must coalesce into a single sheet render');
  });

  testWidgets('notifyBlocked is a no-op when no navigator is attached',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('no nav key'))),
    );

    int calls = 0;
    PremiumUpsellController.showOverride = (_, __) async {
      calls += 1;
    };

    await PremiumUpsellController.notifyBlocked(reason: 'ignored');
    expect(calls, equals(0),
        reason: 'no navigatorKey.currentContext → short-circuit');
  });

  // ── Feature 009: comparación Gratis vs Pro + contador de prueba ──
  //
  // La vista de planes rediseñada (T-22/T-23) muestra una comparación
  // clara con las funciones reales de cada plan y, arriba, el contador
  // de prueba prominente. Estas pruebas cubren AC-06.

  /// Plan Gratis y Pro con funciones reales del spec §8.
  List<SubscriptionPlan> f009Plans() => const [
        SubscriptionPlan(
          id: PlanId.gratis,
          name: 'Gratis',
          description: 'Lo esencial para vender',
          prices: [
            PlanPrice(interval: BillingInterval.mensual, amount: 0)
          ],
          features: [
            'Registrar ventas (POS)',
            'Inventario',
            'Fiado con recordatorios',
            'Clientes',
            'Reportes básicos',
          ],
        ),
        SubscriptionPlan(
          id: PlanId.pro,
          name: 'Pro',
          description: 'Todas las herramientas para crecer',
          prices: [
            PlanPrice(interval: BillingInterval.mensual, amount: 29900),
            PlanPrice(interval: BillingInterval.anual, amount: 299000),
          ],
          features: [
            'Generación de logo con IA',
            'Escaneo de facturas con IA',
            'Voz a catálogo',
            'Catálogo web público',
            'Multi-sede',
          ],
        ),
      ];

  testWidgets(
      'F009: muestra el contador de prueba prominente cuando es TRIAL',
      (tester) async {
    final api = _FakeApi(
      onPlans: () async => f009Plans(),
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.trial,
        plan: PlanId.pro,
        trialDaysRemaining: 8,
        trialTotalDays: 14,
      ),
    );

    await pumpSheet(tester, api: api);

    expect(find.byKey(const Key('premium_upsell_trial_counter')),
        findsOneWidget);
    expect(find.textContaining('8 días'), findsWidgets);
    expect(find.textContaining('prueba Pro'), findsWidgets);
  });

  testWidgets(
      'F009: el contador de prueba no aparece para un tenant FREE',
      (tester) async {
    final api = _FakeApi(
      onPlans: () async => f009Plans(),
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.free,
        plan: PlanId.gratis,
      ),
    );

    await pumpSheet(tester, api: api);

    expect(find.byKey(const Key('premium_upsell_trial_counter')),
        findsNothing);
  });

  testWidgets(
      'F009: la comparación lista las funciones reales de cada plan',
      (tester) async {
    final api = _FakeApi(onPlans: () async => f009Plans());

    await pumpSheet(tester, api: api);

    // Funciones reales del plan Gratis (spec §8).
    expect(find.text('Registrar ventas (POS)'), findsOneWidget);
    expect(find.text('Fiado con recordatorios'), findsOneWidget);
    // Funciones reales del plan Pro (spec §8).
    expect(find.text('Generación de logo con IA'), findsOneWidget);
    expect(find.text('Voz a catálogo'), findsOneWidget);
    expect(find.text('Multi-sede'), findsOneWidget);
  });

  testWidgets(
      'F009: ya no se muestran las viñetas hardcodeadas inexactas',
      (tester) async {
    final api = _FakeApi(onPlans: () async => f009Plans());

    await pumpSheet(tester, api: api);

    // Estas eran las viñetas hardcodeadas de F008 que el spec §8
    // marca como inexactas — no deben aparecer más.
    expect(find.text('Fiar a tus clientes con recordatorios'),
        findsNothing);
    expect(find.text('Mesas, KDS, servicios y combos con IA'),
        findsNothing);
  });

  testWidgets(
      'F009: las tarjetas se apilan en ancho móvil (360dp)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi(onPlans: () async => f009Plans());

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showPremiumUpsellSheet(context, api: api),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gratis = tester.getRect(
        find.byKey(const Key('plan_card_gratis')));
    final pro = tester.getRect(find.byKey(const Key('plan_card_pro')));
    // Apiladas: la tarjeta Pro queda debajo de la Gratis.
    expect(pro.top, greaterThanOrEqualTo(gratis.bottom - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'F009: las tarjetas van lado a lado en ancho de escritorio',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi(onPlans: () async => f009Plans());

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showPremiumUpsellSheet(context, api: api),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final gratis = tester.getRect(
        find.byKey(const Key('plan_card_gratis')));
    final pro = tester.getRect(find.byKey(const Key('plan_card_pro')));
    // Lado a lado: comparten franja vertical, una a la izquierda de la
    // otra.
    expect(gratis.right, lessThanOrEqualTo(pro.left + 1));
    expect(tester.takeException(), isNull);
  });
}
