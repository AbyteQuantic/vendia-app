// Spec: specs/047-offline-sync-contract/spec.md (responsive 360dp — SAT N140)
//
// Guardas de layout para la terminal angosta (SAT N140 ~360dp). Reproducen los
// patrones EXACTOS que dejaron los fixes y verifican que no desbordan a 320dp
// de ancho lógico (el peor caso real de la terminal con bordes del sistema).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 320dp lógicos × dpr 3 → caso angosto de la SAT N140.
  void asNarrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(320 * 3.0, 800 * 3.0);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'selector de mesas: maxCrossAxisExtent adapta columnas sin celdas '
      'ilegibles ni overflow a 320dp', (tester) async {
    asNarrow(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
              itemCount: 12,
              itemBuilder: (_, i) => Container(
                key: ValueKey('mesa-$i'),
                color: Colors.blue,
                alignment: Alignment.center,
                child: const FittedBox(child: Text('Terraza 12 · \$150.000')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // Con 320 - 40 (padding) = 280 útiles y max 110 → 3 columnas ~ (280-20)/3
    // ≈ 86dp: más legible que las celdas de ~72dp del crossAxisCount:4 fijo.
    final tileSize = tester.getSize(find.byKey(const ValueKey('mesa-0')));
    expect(tileSize.width, greaterThan(80));
  });

  testWidgets(
      'barra de mesa activa: nombre largo + badge no desborda el Row a 320dp '
      '(Flexible + ellipsis)', (tester) async {
    asNarrow(tester);

    Widget mesaButton(IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.only(left: 6),
          color: Colors.blue,
          child: Icon(icon, size: 18),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.table_restaurant_rounded, size: 16),
                          const SizedBox(width: 4),
                          // El patrón del fix: Flexible + ellipsis.
                          Flexible(
                            child: Text(
                              'Terraza Principal Salón VIP 12',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              color: Colors.amber,
                              child: const Text('Listo para cobrar',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                mesaButton(Icons.receipt_long_rounded),
                mesaButton(Icons.attach_money_rounded),
                mesaButton(Icons.qr_code_rounded),
                mesaButton(Icons.close_rounded),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
