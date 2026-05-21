// Spec: specs/029-precios-multi-tier/spec.md
//
// T-21: Widget test del OptionalCapabilitiesSection con el toggle
// priceTiers de F029.
//
// Cobertura:
//   - AC-01: con el toggle OFF, los 3 TextField de nombres NO se
//     renderizan (cero UI nueva).
//   - AC-02: al prender el toggle, aparece el sub-formulario con 3
//     TextField prefilleados con los nombres pasados por el padre.
//   - editar uno de los nombres se persiste en el controller, listo
//     para que business_profile_screen lo envíe en el PATCH.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/optional_capabilities_section.dart';

Widget _wrap({
  required ValueNotifier<bool> enablePriceTiers,
  required TextEditingController tier1,
  required TextEditingController tier2,
  required TextEditingController tier3,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OptionalCapabilitiesSection(
          selectedType: 'deposito_construccion',
          flags: const FeatureFlags(),
          offersServices: ValueNotifier<bool>(false),
          sellsByWeight: ValueNotifier<bool>(false),
          hasTables: ValueNotifier<bool>(false),
          enablePriceTiers: enablePriceTiers,
          priceTier1NameCtrl: tier1,
          priceTier2NameCtrl: tier2,
          priceTier3NameCtrl: tier3,
        ),
      ),
    ),
  );
}

void main() {
  group('OptionalCapabilitiesSection — toggle priceTiers (F029)', () {
    testWidgets(
        'AC-01: con priceTiers OFF, los 3 TextField de nombres NO aparecen',
        (tester) async {
      final enable = ValueNotifier<bool>(false);
      final t1 = TextEditingController(text: 'Depósito contado');
      final t2 = TextEditingController(text: 'Depósito crédito');
      final t3 = TextEditingController(text: 'Cliente final');

      await tester.pumpWidget(_wrap(
        enablePriceTiers: enable,
        tier1: t1,
        tier2: t2,
        tier3: t3,
      ));
      await tester.pumpAndSettle();

      // El switch sí debe estar (es la entrada para prenderlo).
      expect(find.byKey(const Key('toggle_price_tiers')), findsOneWidget);
      // Pero el sub-form NO debe estar visible mientras la capacidad está OFF.
      expect(find.byKey(const Key('price_tiers_subform')), findsNothing);
      expect(find.byKey(const Key('price_tier_1_name')), findsNothing);
      expect(find.byKey(const Key('price_tier_2_name')), findsNothing);
      expect(find.byKey(const Key('price_tier_3_name')), findsNothing);
    });

    testWidgets(
        'AC-02: al prender priceTiers aparecen 3 TextField prefilleados',
        (tester) async {
      final enable = ValueNotifier<bool>(false);
      final t1 = TextEditingController(text: 'Depósito contado');
      final t2 = TextEditingController(text: 'Depósito crédito');
      final t3 = TextEditingController(text: 'Cliente final');

      await tester.pumpWidget(_wrap(
        enablePriceTiers: enable,
        tier1: t1,
        tier2: t2,
        tier3: t3,
      ));
      await tester.pumpAndSettle();

      // Tap en el switch para prenderlo
      await tester.tap(find.byKey(const Key('toggle_price_tiers')));
      // AnimatedSize → varios pumps hasta que se asienta.
      await tester.pumpAndSettle();

      // Los 3 TextField aparecen con los nombres pre-cargados
      expect(find.byKey(const Key('price_tier_1_name')), findsOneWidget);
      expect(find.byKey(const Key('price_tier_2_name')), findsOneWidget);
      expect(find.byKey(const Key('price_tier_3_name')), findsOneWidget);

      // Los controllers conservan los valores pasados por el padre.
      expect(t1.text, 'Depósito contado');
      expect(t2.text, 'Depósito crédito');
      expect(t3.text, 'Cliente final');

      // El notifier reflejó el cambio.
      expect(enable.value, isTrue);
    });

    testWidgets(
        'editar un nombre se persiste en el TextEditingController',
        (tester) async {
      final enable = ValueNotifier<bool>(true);
      final t1 = TextEditingController(text: 'Depósito contado');
      final t2 = TextEditingController(text: 'Depósito crédito');
      final t3 = TextEditingController(text: 'Cliente final');

      await tester.pumpWidget(_wrap(
        enablePriceTiers: enable,
        tier1: t1,
        tier2: t2,
        tier3: t3,
      ));
      await tester.pumpAndSettle();

      // Sub-form ya visible (enable.value == true desde el inicio).
      await tester.enterText(
          find.byKey(const Key('price_tier_1_name')), 'Mayorista x12');
      await tester.pumpAndSettle();

      expect(t1.text, 'Mayorista x12');
    });
  });
}
