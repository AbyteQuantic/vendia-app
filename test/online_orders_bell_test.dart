import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/online_orders_bell.dart';

/// KDS Phase-1 dashboard bell contract:
///
///  1. The widget mounts without exceptions even when ApiService
///     cannot be constructed (tests without dotenv fixtures).
///  2. Tapping is a no-op on a brand-new mount (count = 0) — the
///     badge doesn't render, and we don't crash on navigation
///     because the route will happily push OnlineOrdersScreen
///     which survives missing dotenv too.
///  3. Disabled mode stays passive — no Timer is registered.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders without crashing when dotenv is absent', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: OnlineOrdersBell())),
    ));
    await tester.pump();

    expect(find.byKey(const Key('dashboard_orders_bell')), findsOneWidget);
    // No pedidos → no badge visible, only the bell icon.
    expect(find.byKey(const Key('dashboard_orders_badge')), findsNothing);
  });

  testWidgets('disabled mode still mounts and stays idle', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: OnlineOrdersBell(enabled: false))),
    ));
    await tester.pump();

    expect(find.byKey(const Key('dashboard_orders_bell')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_orders_badge')), findsNothing);
  });
}
