import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/dashboard/main_dashboard_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────
//
// The dashboard renders 4 action buttons for a retail (pre_payment) tenant:
// VENDER + FIAR in the top row (flex 3) and INVENTARIO + ADMINISTRAR in
// the second row (flex 2). ADMINISTRAR pushes AdminHubScreen. Tests scoped
// to smoke-check keys and label text — flow navigation beyond the
// dashboard is covered by the Flow A/B/C certification tests.
//
// The SharedPreferences + SecureStorage plugins are not mocked here —
// the dashboard's async loaders fail silently (they already wrap in
// try/catch or rely on sensible defaults), so the first-frame render is
// all we assert on.

Widget _buildDashboard() => const MaterialApp(home: MainDashboardScreen());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MainDashboardScreen', () {
    testWidgets('muestra los 4 botones principales (retail por defecto)',
        (tester) async {
      await tester.pumpWidget(_buildDashboard());
      await tester.pump();

      expect(find.byKey(const Key('btn_vender')), findsOneWidget);
      expect(find.byKey(const Key('btn_fiar')), findsOneWidget);
      expect(find.byKey(const Key('btn_inventario')), findsOneWidget);
      expect(find.byKey(const Key('btn_administrar')), findsOneWidget);
    });

    testWidgets('botón VENDER contiene texto "VENDER"', (tester) async {
      await tester.pumpWidget(_buildDashboard());
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('btn_vender')),
          matching: find.text('VENDER'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('botón ADMINISTRAR contiene texto "ADMINISTRAR"',
        (tester) async {
      await tester.pumpWidget(_buildDashboard());
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('btn_administrar')),
          matching: find.text('ADMINISTRAR'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('VENDER y FIAR comparten ancho (misma fila flex 3)',
        (tester) async {
      await tester.pumpWidget(_buildDashboard());
      await tester.pump();

      final vender = tester.getSize(find.byKey(const Key('btn_vender')));
      final fiar = tester.getSize(find.byKey(const Key('btn_fiar')));

      expect(vender.width, closeTo(fiar.width, 4),
          reason: 'VENDER y FIAR son Expanded en la misma Row → mismo ancho');
      expect(vender.height, closeTo(fiar.height, 4),
          reason: 'VENDER y FIAR viven en la misma Row → misma altura');
    });

    testWidgets('INVENTARIO y ADMINISTRAR comparten ancho (misma fila flex 2)',
        (tester) async {
      await tester.pumpWidget(_buildDashboard());
      await tester.pump();

      final inv = tester.getSize(find.byKey(const Key('btn_inventario')));
      final adm = tester.getSize(find.byKey(const Key('btn_administrar')));

      expect(inv.width, closeTo(adm.width, 4),
          reason: 'Inventario y Administrar comparten la misma Row Expanded');
      expect(inv.height, closeTo(adm.height, 4));
    });
  });
}
