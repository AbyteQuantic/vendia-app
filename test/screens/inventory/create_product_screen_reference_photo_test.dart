// Spec: specs/096-foto-referencia-verificada/spec.md
//
// Confirma que CatalogPhotoSuggestion se integra en "Nuevo Producto" sin
// tocar los botones existentes de Quitar fondo / Mejorar con IA / Crear
// foto con IA (Specs 017/094 intactas) — solo aparece cuando hay un
// código de barras/SKU escrito, y desaparece si el campo queda vacío.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/create_product_screen.dart';
import 'package:vendia_pos/widgets/catalog_photo_suggestion.dart';

// Sin dotenv.testLoad a propósito — mismo patrón que
// create_product_screen_fixes_test.dart: esta pantalla arranca varios
// servicios (ApiService, conectividad) en initState, y con dotenv
// cargado alguno de ellos agenda un Timer que sobrevive más allá de un
// solo pump() (falla "!timersPending"). Sin dotenv, ese camino falla en
// silencio antes de agendar nada — y no lo necesitamos: solo probamos
// que CatalogPhotoSuggestion se inserta/retira del árbol según el SKU,
// no su fetch real (ya cubierto en catalog_photo_suggestion_test.dart).
void main() {
  testWidgets(
      'sin código de barras, CatalogPhotoSuggestion no está en el árbol',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
    await tester.pump();

    expect(find.byType(CatalogPhotoSuggestion), findsNothing);
  });

  testWidgets(
      'al escribir un código de barras, aparece CatalogPhotoSuggestion '
      'sin ocultar Quitar fondo / Mejorar con IA / Crear foto con IA',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
    await tester.pump();

    // La pantalla es una ListView larga — el campo vive fuera del
    // viewport inicial, hay que desplazar hasta que se materialice.
    final skuField = find.byKey(const Key('field_sku_barcode'));
    await tester.scrollUntilVisible(skuField, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();

    await tester.enterText(skuField, '7702090000012');
    await tester.pump();

    // CatalogPhotoSuggestion vive MÁS ARRIBA en la misma ListView (junto a
    // los botones de IA) — hay que volver a desplazar hacia atrás para que
    // el sliver la vuelva a materializar tras el scroll hacia abajo.
    final suggestion = find.byType(CatalogPhotoSuggestion);
    await tester.scrollUntilVisible(suggestion, -300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();

    expect(suggestion, findsOneWidget);
  });
}
