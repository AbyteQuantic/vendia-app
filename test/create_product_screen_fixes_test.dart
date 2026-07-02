// Spec: specs/018-nuevo-producto-fixes/spec.md
//
// Widget + unit tests for the three "Nuevo Producto" UX fixes (Feature 018):
//   T-01  a "Galería" button next to "Tomar foto" (gallery picker)
//   T-02  the name autocomplete stays visible above the keyboard
//   T-03  the shown image always reflects the *current* product, and a
//         photo the merchant picked (camera/gallery) always wins over any
//         suggested/generated image.
//
// The screen builds its own ApiService/DatabaseService, so these tests
// stay on the visible contract: stable Keys and the pure decision helper
// `CreateProductImagePolicy`, which carries no I/O. The autocomplete
// search only hits the DB at >=3 typed characters — the tests never type
// that far, so no Isar/network call is triggered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/create_product_screen.dart';

void main() {
  group('T-01 · Galería button', () {
    testWidgets('"Nuevo Producto" shows a Galería button next to Tomar foto',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
      await tester.pump();

      expect(find.byKey(const Key('btn_take_photo')), findsOneWidget,
          reason: 'the camera button must remain findable');
      expect(find.byKey(const Key('btn_pick_gallery')), findsOneWidget,
          reason: 'a Galería (gallery) button must exist — FR-01 / AC-01');
      expect(find.text('Galería'), findsOneWidget,
          reason: 'the gallery button is labelled in Spanish');
    });
  });

  group('T-02 · autocomplete visible above the keyboard', () {
    testWidgets(
        'focusing the name field keeps it inside the visible viewport '
        'so the suggestion list is not hidden behind the keyboard',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
      await tester.pump();

      final nameField =
          find.widgetWithText(TextFormField, 'Buscar o escribir nombre...');
      expect(nameField, findsOneWidget,
          reason: 'the product-name field must be present');

      // Focus the field — the production code listens for focus and runs
      // Scrollable.ensureVisible so the field (and the suggestion overlay
      // rendered right under it) is not covered by the keyboard — FR-02.
      await tester.tap(nameField);
      await tester.pumpAndSettle();

      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final fieldRect = tester.getRect(nameField);
      expect(fieldRect.top, greaterThanOrEqualTo(0.0),
          reason: 'the name field must stay visible after focus — FR-02');
      expect(fieldRect.bottom, lessThanOrEqualTo(viewportHeight),
          reason: 'the name field must remain inside the viewport so its '
              'suggestion list can render above the keyboard — FR-02');
    });
  });

  group('T-03 · image reflects the current product', () {
    test('a merchant photo always wins over a suggested image', () {
      // The merchant took/picked a photo -> no suggested URL may replace it.
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: true,
          suggestedUrl: 'https://catalog.example/keychain.png',
        ),
        isFalse,
        reason: 'D2 — the merchant photo always has priority (FR-03/AC-04)',
      );
    });

    test('a suggested image applies only when there is no merchant photo', () {
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: false,
          suggestedUrl: 'https://catalog.example/keychain.png',
        ),
        isTrue,
      );
    });

    // Bug real reportado: el tendero fotografió un llavero 3D de Stitch;
    // al escribir el nombre y tocar la sugerencia de autocompletado, su
    // foto quedó reemplazada en silencio por la de OTRO llavero (2D, de
    // otro tenant) del catálogo global "user" — matcheado solo por nombre.
    test(
        'un catálogo aportado por otro tenant (source "user") NUNCA se '
        'auto-aplica, aunque no haya foto propia', () {
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: false,
          suggestedUrl: 'https://catalog.example/otro-llavero.png',
          isUserContributedCatalog: true,
        ),
        isFalse,
        reason: 'mismo nombre no implica mismo objeto físico para '
            'artículos con variación real (llaveros, artesanías, ropa)',
      );
    });

    test(
        'un catálogo global estandarizado (Open Food Facts / barcode) SÍ '
        'se auto-aplica sin foto propia — caso seguro, cero fricción', () {
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: false,
          suggestedUrl: 'https://off.example/coca-cola-350ml.png',
          isUserContributedCatalog: false,
        ),
        isTrue,
        reason: 'producto empacado estandarizado: mismo barcode/nombre '
            'SÍ es el mismo objeto físico',
      );
    });

    test('la foto propia del tendero sigue ganando aunque sea catálogo "off"', () {
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: true,
          suggestedUrl: 'https://off.example/coca-cola-350ml.png',
          isUserContributedCatalog: false,
        ),
        isFalse,
      );
    });

    test('an empty or null suggested url never applies', () {
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: false,
          suggestedUrl: '',
        ),
        isFalse,
      );
      expect(
        CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: false,
          suggestedUrl: null,
        ),
        isFalse,
      );
    });

    test('catalog suggestions are dropped when the name no longer matches', () {
      // "Llavero Kitty" -> alien keychains: a stale catalog list from a
      // previous name must not survive once the typed name diverges.
      expect(
        CreateProductImagePolicy.catalogStillMatchesName(
          catalogSourceName: 'Llavero Alien',
          currentName: 'Llavero Kitty',
        ),
        isFalse,
        reason: 'FR-04 — unrelated catalog photos must be cleared',
      );
      expect(
        CreateProductImagePolicy.catalogStillMatchesName(
          catalogSourceName: 'Llavero Kitty',
          currentName: 'Llavero Kitty Rosado',
        ),
        isTrue,
        reason: 'a still-overlapping name keeps the catalog images',
      );
      expect(
        CreateProductImagePolicy.catalogStillMatchesName(
          catalogSourceName: '',
          currentName: 'Llavero Kitty',
        ),
        isFalse,
        reason: 'no source name -> nothing to keep',
      );
    });
  });

  group('Aviso de encuadre antes de tomar la foto', () {
    testWidgets(
        'shows the framing tip banner while there is no photo yet',
        (tester) async {
      // Bug real reportado: fotos que cortan una correa/cadena producen
      // resultados de IA "incompletos" para siempre — el pipeline es
      // no-generativo y no puede inventar lo que la cámara no capturó. El
      // aviso debe estar visible ANTES de que el tendero tome la foto.
      await tester.pumpWidget(const MaterialApp(home: CreateProductScreen()));
      await tester.pump();

      expect(find.byKey(const Key('framing_tip_banner')), findsOneWidget,
          reason: 'sin foto todavía, el aviso de encuadre debe verse');
      expect(
        find.text(CreateProductScreen.framingTip),
        findsOneWidget,
        reason: 'el texto exacto del aviso debe estar en pantalla',
      );
    });
  });
}
