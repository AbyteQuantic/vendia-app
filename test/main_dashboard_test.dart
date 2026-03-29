import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/screens/dashboard/main_dashboard_screen.dart';
import 'package:vendia_pos/screens/pos/pos_screen.dart';
import 'package:vendia_pos/screens/admin/admin_screen.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

Widget buildDashboard() => MaterialApp(
      routes: {
        '/pos': (_) => ChangeNotifierProvider(
              create: (_) => CartController(),
              child: const PosScreen(),
            ),
        '/admin': (_) => const AdminScreen(),
      },
      home: const MainDashboardScreen(),
    );

void main() {
  group('MainDashboardScreen', () {
    testWidgets('muestra exactamente 2 botones principales', (tester) async {
      await tester.pumpWidget(buildDashboard());

      expect(find.byKey(const Key('btn_vender')), findsOneWidget);
      expect(find.byKey(const Key('btn_administrar')), findsOneWidget);
    });

    testWidgets('botón VENDER contiene texto "VENDER"', (tester) async {
      await tester.pumpWidget(buildDashboard());

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
      await tester.pumpWidget(buildDashboard());

      expect(
        find.descendant(
          of: find.byKey(const Key('btn_administrar')),
          matching: find.text('ADMINISTRAR'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('los 2 botones ocupan proporciones iguales (Expanded)',
        (tester) async {
      await tester.pumpWidget(buildDashboard());

      // Ambos botones deben existir con el mismo ancho (dentro de Expanded)
      final vender = tester.getSize(find.byKey(const Key('btn_vender')));
      final admin = tester.getSize(find.byKey(const Key('btn_administrar')));

      expect(vender.height, closeTo(admin.height, 4),
          reason: 'Ambos botones deben tener la misma altura');
    });

    testWidgets('VENDER navega a PosScreen', (tester) async {
      await tester.pumpWidget(buildDashboard());

      await tester.tap(find.byKey(const Key('btn_vender')));
      await tester.pumpAndSettle();

      expect(find.byType(PosScreen), findsOneWidget);
    });

    testWidgets('ADMINISTRAR navega a AdminScreen', (tester) async {
      await tester.pumpWidget(buildDashboard());

      await tester.tap(find.byKey(const Key('btn_administrar')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminScreen), findsOneWidget);
    });
  });
}
