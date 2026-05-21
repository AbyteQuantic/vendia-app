// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// T-21: Widget test del OptionalCapabilitiesSection con el toggle
// customerManagement de F030.
//
// Cobertura:
//   - AC-02: el toggle "Gestión de clientes" aparece cuando el padre
//     cablea el ValueNotifier.
//   - el toggle persiste el cambio en el ValueNotifier (listo para que
//     business_profile_screen lo envíe en el PATCH).
//   - sin el ValueNotifier cableado el toggle NO se renderiza (mantiene
//     la invariante "no se pinta sin destino donde guardar").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/optional_capabilities_section.dart';

Widget _wrap({ValueNotifier<bool>? enableCustomerManagement}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OptionalCapabilitiesSection(
          selectedType: 'tienda_barrio',
          flags: const FeatureFlags(),
          offersServices: ValueNotifier<bool>(false),
          sellsByWeight: ValueNotifier<bool>(false),
          hasTables: ValueNotifier<bool>(false),
          enableCustomerManagement: enableCustomerManagement,
        ),
      ),
    ),
  );
}

void main() {
  group('OptionalCapabilitiesSection — toggle customerManagement (F030)', () {
    testWidgets(
        'el toggle "Gestión de clientes" aparece cuando el padre lo cablea',
        (tester) async {
      await tester.pumpWidget(
        _wrap(enableCustomerManagement: ValueNotifier<bool>(false)),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('toggle_customer_management')), findsOneWidget);
      expect(find.text('Gestión de clientes'), findsOneWidget);
    });

    testWidgets('sin el ValueNotifier cableado el toggle NO se renderiza',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('toggle_customer_management')), findsNothing);
    });

    testWidgets('al prender el toggle el ValueNotifier persiste true',
        (tester) async {
      final notifier = ValueNotifier<bool>(false);
      await tester.pumpWidget(_wrap(enableCustomerManagement: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toggle_customer_management')));
      await tester.pumpAndSettle();

      expect(notifier.value, isTrue);
    });

    testWidgets('al apagar el toggle el ValueNotifier persiste false',
        (tester) async {
      final notifier = ValueNotifier<bool>(true);
      await tester.pumpWidget(_wrap(enableCustomerManagement: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toggle_customer_management')));
      await tester.pumpAndSettle();

      expect(notifier.value, isFalse);
    });
  });
}
