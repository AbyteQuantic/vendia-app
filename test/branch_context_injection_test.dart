import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/models/branch.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/branch_provider.dart';
import 'package:vendia_pos/screens/dashboard/main_dashboard_screen.dart';

/// Phase-6 branch isolation — Flutter side.
///
/// The contract under test:
///
///  1. `BranchProvider.selectBranch` mirrors the pick onto
///     `ApiService.currentBranchId`. That static is what every
///     operational read / write picks up as the `branch_id` scope,
///     so keeping the two in sync IS the isolation guarantee on the
///     client.
///  2. `BranchProvider.reset()` (logout / session clear) nulls the
///     static so a brand-new session doesn't inherit the previous
///     tenant's sede context.
///  3. The dashboard chip renders `📍 Operando en: <sede>` whenever
///     a sede is selected, reads from the same provider, and
///     degrades to SizedBox.shrink() when the provider isn't in the
///     tree (so the widget is safe in smoke tests).

Branch _branch(String id, String name, {bool isDefault = false}) => Branch(
      id: id,
      tenantId: 't-1',
      name: name,
      isDefault: isDefault,
      createdAt: DateTime(2026, 4, 23),
    );

Widget _wrapWithProvider(BranchProvider provider, Widget child) {
  return ChangeNotifierProvider<BranchProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiService.currentBranchId = null;
  });

  tearDown(() {
    ApiService.currentBranchId = null;
  });

  group('BranchProvider ↔ ApiService.currentBranchId sync', () {
    test('selectBranch mirrors the id onto ApiService.currentBranchId', () {
      final provider = BranchProvider();
      final norte = _branch('11111111-1111-1111-1111-111111111111', 'Norte');
      final sur = _branch('22222222-2222-2222-2222-222222222222', 'Sur');
      provider.setBranches([norte, sur]);

      // setBranches auto-selects the default (or the first) — that
      // already populates the static, so we start from a known
      // state and then flip the selection.
      provider.selectBranch(sur);

      expect(ApiService.currentBranchId, sur.id,
          reason: 'selectBranch must sync onto the static so the next'
              ' fetchProducts/createSale call attaches the sede scope');
    });

    test('setBranches picks the default branch and syncs onto the static', () {
      final provider = BranchProvider();
      final principal = _branch('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          'Principal', isDefault: true);
      final otra = _branch('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Otra');
      provider.setBranches([otra, principal]);

      expect(ApiService.currentBranchId, principal.id,
          reason: 'default branch wins on first load even when it is not first');
    });

    test('reset() clears the static so a new session starts clean', () {
      final provider = BranchProvider();
      provider.setBranches([
        _branch('33333333-3333-3333-3333-333333333333', 'Única',
            isDefault: true),
      ]);
      expect(ApiService.currentBranchId, isNotNull);

      provider.reset();

      expect(ApiService.currentBranchId, isNull,
          reason: 'logout must purge the sede scope so next tenant '
              'does not inherit it');
    });

    test('selecting the already-active branch is a no-op on the static', () {
      final provider = BranchProvider();
      final only = _branch('44444444-4444-4444-4444-444444444444', 'Única',
          isDefault: true);
      provider.setBranches([only]);

      final first = ApiService.currentBranchId;
      provider.selectBranch(only); // re-select the same one
      expect(ApiService.currentBranchId, first);
    });
  });

  group('Dashboard branch chip', () {
    testWidgets('renders "Operando en: <sede>" when a branch is active',
        (tester) async {
      final provider = BranchProvider();
      provider.setBranches([
        _branch('55555555-5555-5555-5555-555555555555', 'Sede Norte',
            isDefault: true),
      ]);

      await tester.pumpWidget(_wrapWithProvider(
        provider,
        const MainDashboardScreen(),
      ));
      await tester.pump(); // let initState / futures settle

      expect(find.byKey(const Key('dashboard_branch_chip')), findsOneWidget);
      expect(find.textContaining('Operando en: Sede Norte'), findsOneWidget);
    });

    testWidgets('hides the chip when no branch is loaded yet', (tester) async {
      final provider = BranchProvider(); // empty — no fetch yet

      await tester.pumpWidget(_wrapWithProvider(
        provider,
        const MainDashboardScreen(),
      ));
      await tester.pump();

      expect(find.byKey(const Key('dashboard_branch_chip')), findsNothing,
          reason: 'blank chip would flash while the first fetch is in flight');
    });

    testWidgets('shows the swap-horiz affordance only for multi-sede tenants',
        (tester) async {
      final provider = BranchProvider();
      provider.setBranches([
        _branch('66666666-6666-6666-6666-666666666666', 'Norte',
            isDefault: true),
        _branch('77777777-7777-7777-7777-777777777777', 'Sur'),
      ]);

      await tester.pumpWidget(_wrapWithProvider(
        provider,
        const MainDashboardScreen(),
      ));
      await tester.pump();

      // The chip renders an Icons.swap_horiz_rounded when isMultiBranch.
      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    });

    testWidgets('chip is absent without the Provider (no crash in isolation)',
        (tester) async {
      // The `main_dashboard_test.dart` smoke tests don't install a
      // BranchProvider. The chip must degrade to SizedBox.shrink()
      // via the ProviderNotFoundException try/catch instead of
      // tearing down the whole dashboard tree.
      await tester.pumpWidget(
        const MaterialApp(home: MainDashboardScreen()),
      );
      await tester.pump();

      expect(find.byKey(const Key('dashboard_branch_chip')), findsNothing);
      // The rest of the dashboard (VENDER button) still renders.
      expect(find.byKey(const Key('btn_vender')), findsOneWidget);
    });
  });
}
