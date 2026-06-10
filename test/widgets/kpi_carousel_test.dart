// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Tests del carrusel inmersivo de KPIs del Dashboard.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/kpi_carousel.dart';

void main() {
  testWidgets('Sin cards → no renderea nada', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: KpiCarousel(cards: [])),
    ));
    // No hay PageView ni indicador de dots — todo SizedBox.shrink.
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('Con 3 cards → renderea PageView con dots indicator',
      (tester) async {
    final cards = [
      KpiCardData(
        title: 'Ventas hoy',
        value: r'$50.000',
        photoUrl: '',
        fallbackIcon: Icons.trending_up_rounded,
        accentColor: Colors.blue,
        onTap: () {},
      ),
      KpiCardData(
        title: 'Más vendido',
        value: 'Coca-Cola',
        photoUrl: '',
        fallbackIcon: Icons.star_rounded,
        accentColor: Colors.amber,
        onTap: () {},
      ),
      KpiCardData(
        title: 'Inventario',
        value: '20 ref.',
        photoUrl: '',
        fallbackIcon: Icons.inventory_2_rounded,
        accentColor: Colors.indigo,
        onTap: () {},
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KpiCarousel(cards: cards)),
    ));
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    // Tras el rediseño foto-arriba/info-abajo el título se muestra tal
    // cual (sin uppercase) y el valor se pinta en grande con color de
    // acento. Solo verificamos presencia.
    expect(find.text('Ventas hoy'), findsOneWidget);
    expect(find.text(r'$50.000'), findsOneWidget);
  });

  testWidgets('Tap en la card central dispara onTap', (tester) async {
    var tapped = false;
    final cards = [
      KpiCardData(
        title: 'Ventas hoy',
        value: r'$0',
        photoUrl: '',
        fallbackIcon: Icons.trending_up_rounded,
        accentColor: Colors.blue,
        onTap: () => tapped = true,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KpiCarousel(cards: cards)),
    ));
    await tester.pump();

    // Tocamos el texto del valor — el InkWell que envuelve la card lo captura.
    await tester.tap(find.text(r'$0'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('onRemove ausente → no se pinta el botón quitar', (tester) async {
    final cards = [
      KpiCardData(
        title: 'Ventas hoy',
        value: r'$0',
        photoUrl: '',
        fallbackIcon: Icons.trending_up_rounded,
        accentColor: Colors.blue,
        onTap: () {},
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KpiCarousel(cards: cards)),
    ));
    await tester.pump();
    // Los KPIs no traen onRemove → sin ícono de cerrar.
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('onRemove presente → botón quitar visible y dispara la acción',
      (tester) async {
    var removed = false;
    final cards = [
      KpiCardData(
        title: 'Eventos',
        value: 'Activo',
        photoUrl: '',
        fallbackIcon: Icons.event_rounded,
        accentColor: Colors.indigo,
        onTap: () {},
        onRemove: () => removed = true,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KpiCarousel(cards: cards)),
    ));
    await tester.pump();

    final removeBtn = find.byIcon(Icons.close_rounded);
    expect(removeBtn, findsOneWidget);
    await tester.tap(removeBtn);
    await tester.pump();
    expect(removed, isTrue);
  });

  testWidgets('Subtitle opcional se renderea cuando viene', (tester) async {
    final cards = [
      KpiCardData(
        title: 'Ventas hoy',
        value: r'$120.000',
        subtitle: '5 ventas',
        photoUrl: '',
        fallbackIcon: Icons.trending_up_rounded,
        accentColor: Colors.blue,
        onTap: () {},
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KpiCarousel(cards: cards)),
    ));
    await tester.pump();

    expect(find.text('5 ventas'), findsOneWidget);
  });
}
