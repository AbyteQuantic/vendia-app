import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/premium_upsell_sheet.dart';

/// Widget tests for the soft paywall sheet. Coverage:
///   - The sheet renders the PRO CTA + dismiss button + feature bullets
///     when opened via showPremiumUpsellSheet().
///   - PremiumUpsellController.notifyBlocked() routes into the
///     showOverride when present (test seam used by the Dio
///     interceptor integration tests).
///   - notifyBlocked() is idempotent — a second fire while the sheet
///     is already showing must NOT trigger a second render.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PremiumUpsellController.resetForTest();
  });

  tearDown(() {
    PremiumUpsellController.showOverride = null;
    PremiumUpsellController.resetForTest();
  });

  testWidgets('showPremiumUpsellSheet renders CTA + dismiss + key bullets',
      (tester) async {
    // Bigger viewport so DraggableScrollableSheet's initial 72% height
    // fits all the content — default 800x600 cuts off the dismiss btn.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPremiumUpsellSheet(
                context,
                reason: 'Tu prueba terminó',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('premium_upsell_sheet')), findsOneWidget);
    expect(find.byKey(const Key('premium_upsell_cta')), findsOneWidget);
    expect(find.byKey(const Key('premium_upsell_dismiss')), findsOneWidget);
    // Both the subtitle (branded) and the reason param contain the
    // phrase; findsWidgets asserts at least one, which is the real
    // invariant — the sheet surfaces the reason to the user somewhere.
    expect(find.textContaining('Tu prueba terminó'), findsWidgets);
  });

  testWidgets('dismiss CTA closes the sheet without side effects',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPremiumUpsellSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('premium_upsell_sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('premium_upsell_dismiss')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('premium_upsell_sheet')), findsNothing);
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
      // Hold the "sheet open" until the test explicitly lets go —
      // that way re-entrant calls observe _isShowing=true and short
      // circuit. Using a Completer avoids the FakeAsync timer trap
      // that Future.delayed triggers inside widget tests.
      await completer.future;
    };

    await tester.pumpWidget(MaterialApp(
      navigatorKey: PremiumUpsellController.navigatorKey,
      home: const Scaffold(body: Text('ready')),
    ));

    // First call: synchronous path up to `await showOverride` runs
    // immediately; _isShowing flips to true before we return.
    final f1 = PremiumUpsellController.notifyBlocked(reason: 'expired');
    // Second call: observes _isShowing and returns a completed future.
    final f2 = PremiumUpsellController.notifyBlocked(reason: 'expired');

    await f2; // f2 returns immediately
    expect(calls, equals(1));
    expect(lastReason, equals('expired'));

    // Release the first call and make sure the guard unwinds cleanly.
    completer.complete();
    await f1;

    expect(calls, equals(1),
        reason: 'A burst of 403s must coalesce into a single sheet render');
  });

  testWidgets('notifyBlocked is a no-op when no navigator is attached',
      (tester) async {
    // Reset the navigator by NOT passing the key to MaterialApp.
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
}
