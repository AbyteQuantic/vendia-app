// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// T-24 — cart_controller tests para la asociación de cliente a la venta.
// Cobertura:
//   - selectedCustomer arranca en null (venta anónima por default).
//   - setCustomer(customer) actualiza el estado y notifica.
//   - salePayloadCustomerId expone el id del cliente para el payload de
//     createSale.
//   - setCustomer(null) limpia el cliente → la venta vuelve a anónima.
//   - F029 no se rompe: el tier de precios sigue funcionando junto al
//     cliente seleccionado (coexistencia).

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/models/customer.dart';
import 'package:vendia_pos/models/product.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Customer maria() => const Customer(
        id: 'cust-maria-uuid',
        name: 'María Pérez',
        phone: '3001112233',
      );

  group('CartController · selectedCustomer (F030)', () {
    test('selectedCustomer arranca en null — venta anónima por default', () {
      final ctrl = CartController();
      expect(ctrl.selectedCustomer, isNull);
      expect(ctrl.salePayloadCustomerId, isNull);
    });

    test('setCustomer(customer) actualiza el estado y notifica', () {
      final ctrl = CartController();
      int notifyCount = 0;
      ctrl.addListener(() => notifyCount++);

      ctrl.setCustomer(maria());

      expect(ctrl.selectedCustomer, isNotNull);
      expect(ctrl.selectedCustomer!.name, 'María Pérez');
      expect(notifyCount, 1);
    });

    test('salePayloadCustomerId expone el id del cliente seleccionado', () {
      final ctrl = CartController();
      ctrl.setCustomer(maria());
      expect(ctrl.salePayloadCustomerId, 'cust-maria-uuid');
    });

    test('setCustomer(null) limpia el cliente → venta vuelve a anónima', () {
      final ctrl = CartController();
      ctrl.setCustomer(maria());
      expect(ctrl.selectedCustomer, isNotNull);

      ctrl.setCustomer(null);

      expect(ctrl.selectedCustomer, isNull);
      expect(ctrl.salePayloadCustomerId, isNull);
    });

    test('cliente con id vacío no aporta customer_id al payload', () {
      final ctrl = CartController();
      ctrl.setCustomer(const Customer(id: '', name: 'Sin id'));
      // Defensive: un cliente sin uuid no debe contaminar el payload.
      expect(ctrl.salePayloadCustomerId, isNull);
    });

    test('setCustomer notifica solo cuando el cliente cambia de verdad', () {
      final ctrl = CartController();
      int notifyCount = 0;
      ctrl.addListener(() => notifyCount++);

      ctrl.setCustomer(maria());
      ctrl.setCustomer(maria()); // mismo id → no notifica de nuevo
      ctrl.setCustomer(null);
      ctrl.setCustomer(null); // ya estaba null → no notifica

      expect(notifyCount, 2);
    });

    test('cliente y tier de precios (F029) coexisten sin romperse', () {
      final ctrl = CartController();
      ctrl.addProduct(const Product(
        id: 1,
        uuid: 'p-cemento',
        name: 'Cemento',
        price: 28500,
        stock: 100,
        priceTier1: 25000,
      ));
      ctrl.setCustomer(maria());
      ctrl.setPriceTier('tier_1');

      // El cliente sigue seleccionado y el tier aplicó al total.
      expect(ctrl.selectedCustomer!.name, 'María Pérez');
      expect(ctrl.selectedPriceTier, 'tier_1');
      expect(ctrl.activeTotal, closeTo(25000, 0.01));
    });

    test('clearActiveCart también limpia el cliente seleccionado', () {
      final ctrl = CartController();
      ctrl.setCustomer(maria());
      ctrl.clearActiveCart();
      expect(ctrl.selectedCustomer, isNull);
    });
  });
}
