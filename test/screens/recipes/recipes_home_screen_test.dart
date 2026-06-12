// Spec: specs/043-menu-restaurante-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/recipes/recipes_home_screen.dart';

void main() {
  group('RecipesHomeScreen (F043)', () {
    testWidgets('muestra las 3 opciones de entrada', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RecipesHomeScreen()));
      await tester.pump();

      expect(find.byKey(const Key('recipes_option_camera')), findsOneWidget);
      expect(find.byKey(const Key('recipes_option_manual')), findsOneWidget);
      expect(find.byKey(const Key('recipes_option_voice')), findsOneWidget);

      expect(find.text('Importar menú desde la cámara'), findsOneWidget);
      expect(find.text('Crear plato o receta'), findsOneWidget);
      expect(find.text('Dictar receta desde el micrófono'), findsOneWidget);
    });

    testWidgets('la cámara abre el selector de fuente (foto / galería)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RecipesHomeScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('recipes_option_camera')));
      await tester.pumpAndSettle(); // anima el bottom sheet

      expect(find.byKey(const Key('menu_source_camera')), findsOneWidget);
      expect(find.byKey(const Key('menu_source_gallery')), findsOneWidget);
      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Elegir de la galería'), findsOneWidget);
    });
  });
}
