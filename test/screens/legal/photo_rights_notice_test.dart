// Spec: specs/098-aporte-automatico-fotos-colaborativo/spec.md
//
// Verifica el aviso ÚNICO de derechos sobre las fotos (Adenda A):
// - Se muestra la primera vez y setea la bandera al confirmar.
// - No se vuelve a mostrar una segunda vez (ya confirmado en el dispositivo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/legal/photo_rights_notice.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget harness(VoidCallback onTap) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => maybeShowPhotoRightsNotice(ctx).then((_) {
                  onTap();
                }),
                child: const Text('subir'),
              ),
            ),
          ),
        ),
      );

  testWidgets('primera vez muestra el aviso y setea la bandera al confirmar',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(harness(() => completed = true));

    await tester.tap(find.text('subir'));
    await tester.pumpAndSettle();

    // El diálogo aparece.
    expect(find.text('Sobre las fotos que sube'), findsOneWidget);
    expect(find.text('Entendido'), findsOneWidget);

    // Confirmar.
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPhotoRightsAckKey), isTrue);
  });

  testWidgets('segunda vez (bandera ya en true) no muestra nada',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPhotoRightsAckKey: true});

    var completed = false;
    await tester.pumpWidget(harness(() => completed = true));

    await tester.tap(find.text('subir'));
    await tester.pumpAndSettle();

    // No hay diálogo; el flujo continúa de inmediato.
    expect(find.text('Sobre las fotos que sube'), findsNothing);
    expect(completed, isTrue);
  });
}
