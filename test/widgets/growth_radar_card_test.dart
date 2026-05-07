import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/growth_radar_card.dart';

/// Widget tests for [GrowthRadarCard]. Each test pumps the card
/// inside a minimal MaterialApp (with explicit size) and asserts on
/// the rendered widget tree.
Future<void> _pumpCard(
  WidgetTester tester, {
  required double revenue,
  required int threshold,
  bool compact = false,
  bool taxAlreadyActive = false,
  VoidCallback? onActivateTaxTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: GrowthRadarCard(
              revenue: revenue,
              threshold: threshold,
              compact: compact,
              taxAlreadyActive: taxAlreadyActive,
              onActivateTaxTap: onActivateTaxTap,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders subtitle with revenue + threshold at 50%',
      (tester) async {
    await _pumpCard(tester, revenue: 80000000, threshold: 160000000);

    // Subtitle should reference both formatted amounts.
    expect(find.textContaining(r'$80.000.000'), findsOneWidget);
    expect(find.textContaining(r'$160.000.000'), findsOneWidget);
    // % numeric is shown in the headline row.
    expect(find.text('50%'), findsOneWidget);
    // 50% lands in the onTrack band.
    expect(find.text('Va por buen camino'), findsOneWidget);
  });

  testWidgets('taxAlreadyActive=true → IVA Configurado pill, no CTA',
      (tester) async {
    await _pumpCard(
      tester,
      revenue: 150000000, // 93.75% → celebrating band → CTA region active
      threshold: 160000000,
      taxAlreadyActive: true,
      onActivateTaxTap: () {},
    );

    expect(find.text('✅ IVA Configurado'), findsOneWidget);
    expect(find.text('Activar IVA'), findsNothing);
  });

  testWidgets('pct≥85% && tax inactive → CTA visible', (tester) async {
    var tapped = false;
    await _pumpCard(
      tester,
      revenue: 150000000, // 93.75% → celebrating
      threshold: 160000000,
      taxAlreadyActive: false,
      onActivateTaxTap: () => tapped = true,
    );

    expect(find.text('Activar IVA'), findsOneWidget);
    expect(find.text('✅ IVA Configurado'), findsNothing);

    await tester.tap(find.text('Activar IVA'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('compact=true reduces outer padding vs default',
      (tester) async {
    EdgeInsets paddingFor(GrowthRadarCard card) {
      // Inspect the outermost Container's padding directly. We find
      // it by looking up the descendant Container inside our card —
      // there is exactly one Container at the root of the build tree.
      final containerFinder = find.descendant(
        of: find.byWidget(card),
        matching: find.byType(Container),
      );
      final container =
          tester.widgetList<Container>(containerFinder).first;
      return container.padding! as EdgeInsets;
    }

    const full = GrowthRadarCard(
      revenue: 80000000,
      threshold: 160000000,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: full)));
    await tester.pump();
    final fullPadding = paddingFor(full);

    const compact = GrowthRadarCard(
      revenue: 80000000,
      threshold: 160000000,
      compact: true,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: compact)));
    await tester.pump();
    final compactPadding = paddingFor(compact);

    expect(compactPadding.top < fullPadding.top, isTrue,
        reason:
            'compact must shrink padding (got compact=${compactPadding.top}, full=${fullPadding.top})');
  });

  testWidgets('rendered tree contains zero threatening/regulatory copy',
      (tester) async {
    // Sweep all bands by pumping at strategic percentages so every
    // band style + headline lands in the tree at least once across
    // the test run.
    final scenarios = <double>[0.1, 0.55, 0.78, 0.9, 1.05];
    const banned = ['DIAN', 'sanción', 'sancion', 'multa', 'Multa', 'rojo'];

    for (final ratio in scenarios) {
      const threshold = 160000000;
      final revenue = (ratio * threshold).toDouble();
      await _pumpCard(
        tester,
        revenue: revenue,
        threshold: threshold,
        taxAlreadyActive: false,
        onActivateTaxTap: () {},
      );

      final allTextWidgets = tester.widgetList<Text>(find.byType(Text));
      final allText =
          allTextWidgets.map((w) => w.data ?? '').join(' ');

      for (final word in banned) {
        expect(allText.contains(word), isFalse,
            reason:
                'Banned word "$word" surfaced at ratio=$ratio in: $allText');
      }
    }
  });
}
