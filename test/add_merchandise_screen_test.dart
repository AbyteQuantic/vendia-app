import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/add_merchandise_screen.dart';

/// Contract tests for the invoice source bottom sheet.
///
/// The UX regression we're pinning here: tapping "Leer Factura del
/// Proveedor" must present a source chooser (camera OR gallery),
/// NOT jump straight into the camera. These tests would have
/// caught the bug last sprint; kept tight on the visible contract
/// so they don't regress on cosmetic redesigns.
void main() {
  testWidgets(
      'tapping the giant invoice button opens the source bottom sheet '
      'instead of launching the camera directly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AddMerchandiseScreen(),
    ));

    // The main CTA is the GestureDetector wrapping the camera icon
    // + "Leer Factura del Proveedor" label. We locate it by its
    // Key — the production code pins that key exactly to survive
    // future visual tweaks.
    final invoiceButton = find.byKey(const Key('btn_read_invoice'));
    expect(invoiceButton, findsOneWidget,
        reason: 'the giant "Leer Factura" button must be findable '
            'by stable key for integration-style assertions');

    await tester.tap(invoiceButton);
    await tester.pumpAndSettle();

    // Both source options must be present in the modal. If the
    // production code regresses to calling ImagePicker directly
    // these finders return nothing.
    expect(
      find.byKey(const Key('invoice_source_camera')),
      findsOneWidget,
      reason: 'camera option must appear in the bottom sheet',
    );
    expect(
      find.byKey(const Key('invoice_source_gallery')),
      findsOneWidget,
      reason: 'gallery option must appear in the bottom sheet',
    );

    // Visible copy is part of the contract — these strings are
    // what the cashier reads before tapping.
    expect(find.text('Tomar foto con la cámara'), findsOneWidget);
    expect(find.text('Subir foto desde la galería'), findsOneWidget);
    expect(find.text('¿De dónde viene la factura?'), findsOneWidget);
  });

  testWidgets(
      'the button subtitle advertises both input methods, not just the camera',
      (tester) async {
    // Prevents a silent UX regression where we'd swap the bottom
    // sheet back in but forget to update the label, leaving
    // "Toque para abrir la cámara" in place and hiding the
    // gallery affordance.
    await tester.pumpWidget(const MaterialApp(
      home: AddMerchandiseScreen(),
    ));
    expect(find.text('Toque para tomar o subir la foto'), findsOneWidget);
    expect(find.text('Toque para abrir la cámara'), findsNothing);
  });
}
