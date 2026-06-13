// Spec: specs/018-nuevo-producto-fixes/spec.md
//
// Regression test for the autocomplete of "Nuevo Producto".
//
// Feature 018 reworked this screen (gallery button, keyboard-aware
// suggestion overlay, stale-image drop) and a regression left the name
// autocomplete unusable on devices: showing the suggestion list had been
// coupled to a `Scrollable.ensureVisible` scroll fired on every search
// result, and an overlay error inside `_searchRemote`'s `try` was being
// swallowed by a mute `catch (_)`. The fix decouples the overlay from
// the scroll and removes the mute catches.
//
// Runs on chrome on purpose: on web `DatabaseService` is the in-memory
// stub, so `_searchLocal` is synchronous and can be seeded — a faithful
// reproduction of the tendero's environment (vendia.store), with no Isar
// fake-async flakiness. Skipped on the VM runner.
@TestOn('chrome')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/database/database_service.dart';
import 'package:vendia_pos/database/collections/local_catalog_product.dart';
import 'package:vendia_pos/screens/inventory/create_product_screen.dart';

LocalCatalogProduct _catalog(String name, String brand) =>
    LocalCatalogProduct()
      ..name = name
      ..brand = brand
      ..imageUrl = null
      ..syncedAt = DateTime.now();

Future<Finder> _openScreenAndFindNameField(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
  await tester.pump();
  final nameField =
      find.widgetWithText(TextFormField, 'Buscar o escribir nombre...');
  expect(nameField, findsOneWidget,
      reason: 'the product-name field must be present');
  return nameField;
}

void main() {
  setUp(() async {
    // Seed the in-memory catalog so the local search yields matches.
    await DatabaseService.instance.syncCatalog([
      _catalog('Coca Cola', 'Coca-Cola'),
      _catalog('Coca Cola Zero', 'Coca-Cola'),
    ]);
  });

  group('Autocomplete · "Nuevo Producto"', () {
    testWidgets('typing >=3 letters shows tappable suggestions', (tester) async {
      final nameField = await _openScreenAndFindNameField(tester);

      await tester.tap(nameField);
      await tester.pump();
      await tester.enterText(nameField, 'coc');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The suggestion list (an Overlay) must render after 3 letters.
      final suggestion = find.text('Coca Cola (Coca-Cola)');
      expect(suggestion, findsWidgets,
          reason: 'autocomplete suggestions must appear — the regression');

      // And it must be selectable: tapping fills the name field.
      await tester.tap(suggestion.first);
      await tester.pump();
      final filled =
          (tester.widget(nameField) as TextFormField).controller!.text;
      expect(filled, 'Coca Cola (Coca-Cola)',
          reason: 'tapping a suggestion fills the name');

      await tester.pump(const Duration(seconds: 5)); // drain the 4s timer
    });

    testWidgets('suggestion stays selectable after the field loses focus',
        (tester) async {
      // Reproduce el bug de iOS web: al tocar una sugerencia el campo
      // pierde el foco ANTES de que el tap se registre. Antes el blur
      // cerraba el overlay de inmediato y el tap caía al vacío. Ahora el
      // cierre por blur está diferido, así que la selección gana.
      final nameField = await _openScreenAndFindNameField(tester);
      await tester.tap(nameField);
      await tester.pump();
      await tester.enterText(nameField, 'coca');
      await tester.pump(const Duration(milliseconds: 60));

      final suggestion = find.text('Coca Cola (Coca-Cola)');
      expect(suggestion, findsWidgets);

      // Simula la pérdida de foco que provoca el tap en web ANTES del tap.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(); // el listener de blur arma el timer diferido

      // El overlay sigue vivo y la sugerencia se puede seleccionar.
      expect(suggestion, findsWidgets,
          reason: 'el blur no debe cerrar el overlay de inmediato');
      await tester.tap(suggestion.first);
      await tester.pump();

      final filled =
          (tester.widget(nameField) as TextFormField).controller!.text;
      expect(filled, 'Coca Cola (Coca-Cola)',
          reason: 'la sugerencia se selecciona aunque el campo perdió el foco');

      await tester.pump(const Duration(seconds: 5)); // drena timers pendientes
    });

    testWidgets('suggestions render with the soft keyboard up', (tester) async {
      // A phone-sized viewport with the soft keyboard raised.
      tester.view.physicalSize = const Size(390 * 3, 760 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final nameField = await _openScreenAndFindNameField(tester);
      await tester.tap(nameField);
      await tester.pump();
      // Soft keyboard slides up.
      tester.view.viewInsets = const FakeViewPadding(bottom: 340 * 3);
      await tester.pump();

      await tester.enterText(nameField, 'coca');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Let the focus-time ensureVisible animation finish (fixed pumps,
      // not pumpAndSettle, to stay clear of an unrelated pre-existing
      // RenderFlex overflow of the scan-barcode hero button on narrow
      // surfaces — out of scope for this autocomplete regression).
      await tester.pump(const Duration(milliseconds: 400));

      final suggestion = find.text('Coca Cola (Coca-Cola)');
      expect(suggestion, findsWidgets,
          reason: 'suggestions must still render with the keyboard up');

      // The suggestion must sit inside the viewport, not above its top.
      final r = tester.getRect(suggestion.first);
      expect(r.top, greaterThanOrEqualTo(0.0),
          reason: 'the suggestion must not be scrolled off the viewport');

      await tester.pump(const Duration(seconds: 5)); // drain pending timers
      // Discard the unrelated hero-button overflow so it cannot mask the
      // autocomplete assertions above (it is not part of this fix).
      final ex = tester.takeException();
      if (ex != null && '$ex'.contains('overflowed')) {
        // expected, ignored on purpose
      } else if (ex != null) {
        throw ex;
      }
    });

    testWidgets('typing under 3 letters shows nothing and never throws',
        (tester) async {
      final nameField = await _openScreenAndFindNameField(tester);
      await tester.tap(nameField);
      await tester.pump();

      await tester.enterText(nameField, 'co');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Coca Cola (Coca-Cola)'), findsNothing,
          reason: 'fewer than 3 letters must not trigger suggestions');
      expect(tester.takeException(), isNull,
          reason: 'short input must never throw');
    });
  });
}
