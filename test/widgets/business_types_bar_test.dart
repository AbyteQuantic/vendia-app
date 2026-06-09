import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/business_types_bar.dart';

/// Tests de la barra de tipos de negocio del Dashboard:
///   - pinta un chip por tipo + el botón "Agregar".
///   - tocar "Agregar" dispara onAdd.
///   - mantener presionado un chip 2s dispara onDelete con su valor.
///   - soltar antes de 2s NO elimina y muestra la pista.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required List<String> types,
    VoidCallback? onAdd,
    ValueChanged<String>? onDelete,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BusinessTypesBar(
          types: types,
          onAdd: onAdd ?? () {},
          onDelete: onDelete ?? (_) {},
        ),
      ),
    ));
  }

  testWidgets('pinta un chip por tipo + el botón Agregar', (tester) async {
    await pumpBar(tester, types: ['tienda_barrio', 'restaurante']);

    expect(find.text('Tienda de Barrio'), findsOneWidget);
    expect(find.text('Restaurante'), findsOneWidget);
    expect(find.text('Agregar'), findsOneWidget);
  });

  testWidgets('sin tipos solo muestra Agregar', (tester) async {
    await pumpBar(tester, types: const []);
    expect(find.text('Agregar'), findsOneWidget);
  });

  testWidgets('tocar Agregar dispara onAdd', (tester) async {
    var added = 0;
    await pumpBar(tester, types: ['tienda_barrio'], onAdd: () => added++);

    await tester.tap(find.text('Agregar'));
    await tester.pump();

    expect(added, 1);
  });

  testWidgets('mantener presionado 2s elimina el tipo', (tester) async {
    String? deleted;
    await pumpBar(
      tester,
      types: ['tienda_barrio', 'restaurante'],
      onDelete: (t) => deleted = t,
    );

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Restaurante')));
    // Antes de los 2s no debe haberse eliminado.
    await tester.pump(const Duration(seconds: 1));
    expect(deleted, isNull);
    // Pasados los 2s, sí.
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    expect(deleted, 'restaurante');
    await gesture.up();
    await tester.pump();
  });

  testWidgets('soltar antes de 2s NO elimina y muestra la pista',
      (tester) async {
    String? deleted;
    await pumpBar(
      tester,
      types: ['tienda_barrio', 'restaurante'],
      onDelete: (t) => deleted = t,
    );

    final gesture = await tester
        .startGesture(tester.getCenter(find.text('Tienda de Barrio')));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pump();

    expect(deleted, isNull);
    expect(find.textContaining('Mantenga presionado'), findsOneWidget);
  });
}
