// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/stock_badge.dart';

void main() {
  testWidgets('un plato de menú muestra "Plato de menú", no "AGOTADO"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StockBadge(stock: 0, isMenuItem: true)),
    ));
    expect(find.text('Plato de menú'), findsOneWidget);
    expect(find.text('AGOTADO'), findsNothing);
  });

  testWidgets('un producto normal con stock 0 sí muestra "AGOTADO"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StockBadge(stock: 0)),
    ));
    expect(find.text('AGOTADO'), findsOneWidget);
    expect(find.text('Plato de menú'), findsNothing);
  });
}
