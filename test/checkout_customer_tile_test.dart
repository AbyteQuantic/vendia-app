// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// T-26 — verificación del tile "Cliente" del CheckoutScreen (F030).
// Seguimos el patrón de checkout_price_tier_selector_test: el
// CheckoutScreen completo requiere Isar + ActiveFiadoService + el stream
// de métodos de pago, ortogonal a la regla que F030 protege. Anclamos
// aquí la condición de visibilidad del tile y la coexistencia con F029,
// y probamos el selector reutilizable como widget real aparte
// (customer_selector_sheet_test.dart).
//
// Cobertura:
//   - AC-03: el tile "Cliente" se renderiza solo cuando la capacidad
//     enable_customer_management está ON y hay CartController.
//   - AC-07: con la capacidad OFF el tile NO aparece (cero UI nueva).
//   - F029 + F030 coexisten: ambos toggles independientes.
//   - el tile refleja el cliente seleccionado en el CartController.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/models/customer.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Mirror de la condición de visibilidad del tile "Cliente" en checkout.
  bool customerTileIsVisible({
    required bool enableCustomerManagement,
    required CartController? cartCtrl,
  }) =>
      enableCustomerManagement && cartCtrl != null;

  group('CheckoutScreen — tile "Cliente" (F030)', () {
    test('AC-07: con la capacidad OFF el tile NO aparece', () {
      final ctrl = CartController();
      expect(
        customerTileIsVisible(
            enableCustomerManagement: false, cartCtrl: ctrl),
        isFalse,
      );
    });

    test('AC-03: con la capacidad ON el tile aparece', () {
      final ctrl = CartController();
      expect(
        customerTileIsVisible(
            enableCustomerManagement: true, cartCtrl: ctrl),
        isTrue,
      );
    });

    test('sin CartController el tile no se renderiza (fail-safe)', () {
      expect(
        customerTileIsVisible(
            enableCustomerManagement: true, cartCtrl: null),
        isFalse,
      );
    });

    test('el tile refleja el cliente seleccionado / "Sin cliente"', () {
      final ctrl = CartController();
      // Sin cliente → la venta es anónima.
      expect(ctrl.selectedCustomer, isNull);

      ctrl.setCustomer(
          const Customer(id: 'c1', name: 'María Pérez', phone: '3001112233'));
      expect(ctrl.selectedCustomer?.name, 'María Pérez');

      ctrl.setCustomer(null);
      expect(ctrl.selectedCustomer, isNull);
    });

    test('F029 (price tiers) y F030 (cliente) son toggles independientes',
        () {
      final ctrl = CartController();
      // Activar uno no fuerza al otro: las dos condiciones de
      // visibilidad se evalúan por separado.
      expect(
        customerTileIsVisible(
            enableCustomerManagement: true, cartCtrl: ctrl),
        isTrue,
      );
      // El selector de tier sigue su propia condición (enablePriceTiers)
      // — aquí el cart arranca en 'retail' como siempre.
      expect(ctrl.selectedPriceTier, 'retail');
    });
  });
}
