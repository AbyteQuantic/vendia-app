// Spec: specs/101-retocar-fotos-inventario/spec.md
//
// UI normalizada de las tarjetas de retoque: bajo el theme REAL de la app
// (cuyo theme legacy de botones es 64dp/22px), Descartar/Confirmar usan el
// kit AppButton y "Mejorar foto" el botón compacto compartido — cero
// overflow a 360dp y tap targets ≥ 44dp. Solo presentación: los callbacks
// se disparan igual.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/theme/app_theme.dart';
import 'package:vendia_pos/widgets/retouch_cards.dart';

const _longName =
    'Chocolatina de maní con leche entera edición especial 500 g';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  testWidgets('RetouchReviewCard a 360dp: sin overflow, Descartar/Confirmar '
      'en una fila con tap target ≥ 44dp y callbacks intactos', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var confirmed = 0;
    var discarded = 0;
    await tester.pumpWidget(_wrap(RetouchReviewCard(
      name: _longName,
      originalUrl: '',
      candidateUrl: '',
      busy: false,
      onConfirm: () => confirmed++,
      onDiscard: () => discarded++,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull); // cero overflow a 360dp

    final dyDescartar = tester.getCenter(find.text('Descartar')).dy;
    final dyConfirmar = tester.getCenter(find.text('Confirmar')).dy;
    expect(dyConfirmar, moreOrLessEquals(dyDescartar, epsilon: 1.0));

    final btn = find
        .ancestor(
            of: find.text('Descartar'), matching: find.byType(OutlinedButton))
        .first;
    expect(tester.getSize(btn).height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Confirmar'));
    await tester.tap(find.text('Descartar'));
    expect(confirmed, 1);
    expect(discarded, 1);
  });

  testWidgets('RetouchPendingCard a 360dp: sin overflow, "Mejorar foto" '
      'compacto (ni gigante ni full-width) y callback intacto', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var taps = 0;
    await tester.pumpWidget(_wrap(RetouchPendingCard(
      name: _longName,
      priceLabel: r'$2.500',
      photoUrl: null,
      busy: false,
      queued: false,
      onRetouch: () => taps++,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull); // cero overflow a 360dp

    final btn = find
        .ancestor(
            of: find.text('Mejorar foto'),
            matching: find.byType(OutlinedButton))
        .first;
    expect(tester.getSize(btn).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(btn).width, lessThan(250)); // no full-width legacy

    await tester.tap(find.text('Mejorar foto'));
    expect(taps, 1);
  });
}
