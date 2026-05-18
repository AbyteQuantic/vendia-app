// Spec: specs/009-trial-visible-vista-planes/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/subscription.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/trial_bar.dart';

/// Widget tests for [TrialBar] — el indicador de prueba del header del
/// Dashboard (Feature 009, T-20). Cubre AC-01..AC-05:
///   - TRIAL  → barra de progreso + "Te quedan N días de prueba Pro".
///   - FREE (trial vencido) → prompt compacto "Activa Pro".
///   - PRO_ACTIVE → no se muestra nada (`SizedBox.shrink`).
///   - Tocar la barra abre la vista de planes.
///   - Si el fetch falla, la barra no se muestra (no bloquea el Dashboard).

/// Fake ApiService: el test controla la única llamada que hace la
/// barra (`fetchSubscriptionStatus`). El doble es mínimo a propósito.
class _FakeApi extends ApiService {
  _FakeApi({this.onStatus}) : super(AuthService());

  final Future<SubscriptionStatus> Function()? onStatus;
  int statusCalls = 0;

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  /// Monta la barra a un ancho móvil (360dp) por defecto.
  Future<void> pumpBar(
    WidgetTester tester, {
    required _FakeApi api,
    VoidCallback? onOpenPlans,
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrialBar(api: api, onOpenPlans: onOpenPlans),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('TRIAL → barra de progreso + "Te quedan 14 días de prueba Pro"',
      (tester) async {
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.trial,
        plan: PlanId.pro,
        trialDaysRemaining: 14,
        trialTotalDays: 14,
      ),
    );

    await pumpBar(tester, api: api);

    expect(find.byKey(const Key('trial_bar')), findsOneWidget);
    expect(find.byKey(const Key('trial_bar_progress')), findsOneWidget);
    expect(find.textContaining('14 días'), findsOneWidget);
    expect(find.textContaining('prueba Pro'), findsOneWidget);
  });

  testWidgets('TRIAL con 5 días usados → la barra refleja 9/14 restantes',
      (tester) async {
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.trial,
        plan: PlanId.pro,
        trialDaysRemaining: 9,
        trialTotalDays: 14,
      ),
    );

    await pumpBar(tester, api: api);

    expect(find.textContaining('9 días'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('trial_bar_progress')),
    );
    // 5 de 14 días consumidos → progreso ≈ 0.357.
    expect(progress.value, closeTo(5 / 14, 0.001));
  });

  testWidgets('TRIAL con 1 día → texto en singular "1 día"',
      (tester) async {
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.trial,
        plan: PlanId.pro,
        trialDaysRemaining: 1,
        trialTotalDays: 14,
      ),
    );

    await pumpBar(tester, api: api);

    expect(find.textContaining('1 día '), findsOneWidget);
  });

  testWidgets('FREE con trial vencido → prompt "Activa Pro" (no barra)',
      (tester) async {
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.free,
        plan: PlanId.gratis,
      ),
    );

    await pumpBar(tester, api: api);

    expect(find.byKey(const Key('trial_bar_upgrade')), findsOneWidget);
    expect(find.byKey(const Key('trial_bar_progress')), findsNothing);
    expect(find.textContaining('Activa Pro'), findsOneWidget);
  });

  testWidgets('PRO_ACTIVE → no se muestra barra ni prompt',
      (tester) async {
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.proActive,
        plan: PlanId.pro,
        interval: BillingInterval.mensual,
      ),
    );

    await pumpBar(tester, api: api);

    expect(find.byKey(const Key('trial_bar')), findsNothing);
    expect(find.byKey(const Key('trial_bar_progress')), findsNothing);
    expect(find.byKey(const Key('trial_bar_upgrade')), findsNothing);
  });

  testWidgets('tocar la barra del trial abre la vista de planes',
      (tester) async {
    var opened = 0;
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.trial,
        plan: PlanId.pro,
        trialDaysRemaining: 7,
        trialTotalDays: 14,
      ),
    );

    await pumpBar(tester, api: api, onOpenPlans: () => opened += 1);

    await tester.tap(find.byKey(const Key('trial_bar')));
    await tester.pumpAndSettle();

    expect(opened, equals(1));
  });

  testWidgets('tocar el prompt "Activa Pro" abre la vista de planes',
      (tester) async {
    var opened = 0;
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.free,
        plan: PlanId.gratis,
      ),
    );

    await pumpBar(tester, api: api, onOpenPlans: () => opened += 1);

    await tester.tap(find.byKey(const Key('trial_bar_upgrade')));
    await tester.pumpAndSettle();

    expect(opened, equals(1));
  });

  testWidgets('si el fetch de estado falla, la barra no se muestra',
      (tester) async {
    final api = _FakeApi(
      onStatus: () async => throw const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión.',
      ),
    );

    await pumpBar(tester, api: api);

    // No bloquea el Dashboard: ni barra, ni prompt, ni error visible.
    expect(find.byKey(const Key('trial_bar')), findsNothing);
    expect(find.byKey(const Key('trial_bar_upgrade')), findsNothing);
    expect(find.textContaining('Sin conexión'), findsNothing);
  });

  testWidgets('TRIAL renderiza sin overflow a 360dp', (tester) async {
    final api = _FakeApi(
      onStatus: () async => const SubscriptionStatus(
        status: SubscriptionStatusValue.trial,
        plan: PlanId.pro,
        trialDaysRemaining: 14,
        trialTotalDays: 14,
      ),
    );

    await pumpBar(tester, api: api, width: 360);

    expect(tester.takeException(), isNull);
  });
}
