// Spec: specs/054-carrusel-navegacion-desktop/spec.md
//
// Tests de los controles de navegación compartidos de carruseles
// (arrastre con mouse, flechas prev/siguiente, dots tocables).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/carousel_navigation.dart';

void main() {
  group('CarouselScrollBehavior', () {
    test('dragDevices incluye mouse y trackpad (AC-01)', () {
      const behavior = CarouselScrollBehavior();
      expect(behavior.dragDevices.contains(PointerDeviceKind.mouse), isTrue);
      expect(behavior.dragDevices.contains(PointerDeviceKind.trackpad), isTrue);
      expect(behavior.dragDevices.contains(PointerDeviceKind.touch), isTrue);
    });
  });

  group('CarouselDots', () {
    testWidgets('count <= 1 → no renderea nada', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CarouselDots(count: 1, current: 0)),
      ));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('tocar un dot dispara onTap con su índice (AC-03)',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CarouselDots(
            count: 4,
            current: 0,
            onTap: (i) => tapped = i,
          ),
        ),
      ));
      // Toca el tercer dot (índice 2).
      await tester.tap(find.byType(InkWell).at(2));
      await tester.pump();
      expect(tapped, 2);
    });

    testWidgets('objetivo táctil ≥ 44dp de alto (AC-03 gerontodiseño)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CarouselDots(count: 3, current: 0, onTap: (_) {}),
        ),
      ));
      final size = tester.getSize(find.byType(InkWell).first);
      expect(size.height, greaterThanOrEqualTo(44.0));
    });
  });

  group('CarouselArrowButton', () {
    testWidgets('renderea chevron correcto y dispara onTap (AC-02)',
        (tester) async {
      var nextTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CarouselArrowButton(
            isNext: true,
            onTap: () => nextTapped = true,
          ),
        ),
      ));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      await tester.tap(find.byType(CarouselArrowButton));
      await tester.pump();
      expect(nextTapped, isTrue);
    });

    testWidgets('isNext false → chevron izquierdo', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CarouselArrowButton(isNext: false, onTap: () {}),
        ),
      ));
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    });
  });
}
