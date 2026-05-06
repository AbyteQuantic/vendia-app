import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hero KPI Wrap with huge ticket prom does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3.0, 800 * 3.0);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              color: Colors.blue,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: const [
                  Text('250 transacciones',
                      style: TextStyle(color: Colors.white)),
                  Text('·', style: TextStyle(color: Colors.white)),
                  Text('Ticket prom. \$1.234.567.890',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
