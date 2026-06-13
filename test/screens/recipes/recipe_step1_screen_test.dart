// Spec: specs/001-insumos-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/recipes/recipe_step1_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  group('RecipeStep1Screen — slice manual F043 (foto + descripción + porción)',
      () {
    testWidgets('renderiza la descripción, las porciones y el toque de foto',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: RecipeStep1Screen()));
      await tester.pump();

      // Foto (tappable), descripción y porciones existen.
      expect(find.byKey(const Key('recipe_photo_tap')), findsOneWidget);
      expect(find.byKey(const Key('field_recipe_description')), findsOneWidget);
      expect(find.byKey(const Key('recipe_portion_Personal')), findsOneWidget);
      expect(find.byKey(const Key('recipe_portion_Para compartir')),
          findsOneWidget);
      expect(find.byKey(const Key('recipe_portion_Familiar')), findsOneWidget);

      // Sin overflow a 360dp (Art. I).
      expect(tester.takeException(), isNull);
    });

    testWidgets('seleccionar una porción la marca; tocarla de nuevo la quita',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: RecipeStep1Screen()));
      await tester.pump();

      ChoiceChip chip() => tester
          .widget<ChoiceChip>(find.byKey(const Key('recipe_portion_Personal')));

      expect(chip().selected, isFalse);

      await tester.tap(find.byKey(const Key('recipe_portion_Personal')));
      await tester.pump();
      expect(chip().selected, isTrue);

      // Toggle off: tocar de nuevo deselecciona (sin porción).
      await tester.tap(find.byKey(const Key('recipe_portion_Personal')));
      await tester.pump();
      expect(chip().selected, isFalse);
    });

    testWidgets('nombre vacío bloquea avanzar y muestra el error',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: RecipeStep1Screen()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_recipe_to_step2')));
      await tester.pump();

      expect(find.text('Escriba el nombre del producto'), findsOneWidget);
    });
  });
}
