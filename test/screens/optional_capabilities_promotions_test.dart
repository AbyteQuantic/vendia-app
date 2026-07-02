// Spec: specs/033-difusion-promociones/spec.md
//
// Widget test del OptionalCapabilitiesSection con el toggle
// "Promociones" de F033 (AC-02).
//
// Cobertura:
//   - el toggle "Promociones" aparece cuando el padre cablea el
//     ValueNotifier.
//   - el toggle persiste el cambio en el ValueNotifier.
//   - sin el ValueNotifier cableado el toggle NO se renderiza.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/optional_capabilities_section.dart';

Widget _wrap({ValueNotifier<bool>? enablePromotions}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OptionalCapabilitiesSection(
          selectedType: 'tienda_barrio',
          flags: const FeatureFlags(),
          offersServices: ValueNotifier<bool>(false),
          sellsByWeight: ValueNotifier<bool>(false),
          hasTables: ValueNotifier<bool>(false),
          enablePromotions: enablePromotions,
        ),
      ),
    ),
  );
}

void main() {
  group('OptionalCapabilitiesSection — toggle promotions (F033)', () {
    testWidgets('el toggle "Promociones" aparece cuando el padre lo cablea',
        (tester) async {
      await tester.pumpWidget(
        _wrap(enablePromotions: ValueNotifier<bool>(false)),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('toggle_promotions')), findsOneWidget);
      expect(find.text('Anuncios por WhatsApp'), findsOneWidget);
    });

    testWidgets('sin el ValueNotifier cableado el toggle NO se renderiza',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_promotions')), findsNothing);
    });

    testWidgets('al activarlo el ValueNotifier pasa a true',
        (tester) async {
      final notifier = ValueNotifier<bool>(false);
      await tester.pumpWidget(_wrap(enablePromotions: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toggle_promotions')));
      await tester.pumpAndSettle();

      expect(notifier.value, isTrue);
    });
  });
}
