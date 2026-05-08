import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/receipt_image_picker.dart';

/// Smoke tests for the receipt picker. We DON'T exercise the full
/// upload roundtrip here (that requires Supabase), but we do pin:
///   * the 8-day legal warning is rendered verbatim,
///   * the default state surfaces the "Adjuntar comprobante" CTA.
void main() {
  testWidgets('renders the literal 8-day legal warning', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptImagePicker(onImageReady: (_) {}),
        ),
      ),
    );

    expect(find.textContaining('se eliminarán de la nube en 8 días'),
        findsOneWidget);
    expect(find.textContaining('Guarde en su galería los que necesite'),
        findsOneWidget);
  });

  testWidgets('default label surfaces the cashier-facing CTA',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptImagePicker(onImageReady: (_) {}),
        ),
      ),
    );
    expect(find.text('Adjuntar comprobante'), findsOneWidget);
  });

  test('legalWarning constant matches the PO-mandated copy', () {
    expect(
      ReceiptImagePicker.legalWarning,
      '⚠️ Estos comprobantes se eliminarán de la nube en 8 días. '
      'Guarde en su galería los que necesite.',
    );
  });
}
