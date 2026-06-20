// Spec: specs/075-proveedores-b2b/spec.md
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/suppliers/supplier_catalog_screen.dart';
import 'package:vendia_pos/screens/suppliers/supplier_inbox_screen.dart';
import 'package:vendia_pos/screens/suppliers/harvest_alerts_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  @override
  Future<Map<String, dynamic>> fetchSupplierCatalog(String id) async => {
        'supplier': {'id': id, 'business_name': '[SEED] El Tomate'},
        'products': [
          {'id': 'p1', 'name': 'Tomate', 'price': 45000, 'expiry_date': '2026-06-23'},
        ],
      };
  @override
  Future<List<Map<String, dynamic>>> fetchSupplierInbox() async => [
        {'id': 'o1', 'buyer_name': 'Tienda Rosa', 'status': 'nuevo', 'total_amount': 90000,
         'delivery_choice': 'tienda_recoge', 'items': jsonEncode([{'name': 'Tomate', 'quantity': 2}])},
      ];
  @override
  Future<List<Map<String, dynamic>>> fetchHarvestAlerts({double radiusKm = 5, int days = 7}) async => [
        {'product_id': 'p1', 'name': 'Tomate', 'days_left': 2, 'nearby_store_count': 6,
         'suggested_message': '¡Oferta! Tomate fresco...'},
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('catálogo del proveedor: stepper suma cantidad y total', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SupplierCatalogScreen(supplierId: 's1', supplierName: '[SEED] El Tomate', api: _FakeApi())));
    await tester.pumpAndSettle();
    expect(find.text('Tomate'), findsOneWidget);
    expect(find.text('Agregue productos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plus_p1')));
    await tester.pump();
    expect(find.textContaining('45000'), findsWidgets); // total refleja el precio
  });

  testWidgets('buzón del proveedor muestra el pedido entrante', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SupplierInboxScreen(api: _FakeApi())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supplier_inbox_list')), findsOneWidget);
    expect(find.text('Tienda Rosa'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
  });

  testWidgets('anti-merma muestra alerta + botón copiar', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HarvestAlertsScreen(api: _FakeApi())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('harvest_alerts_list')), findsOneWidget);
    expect(find.text('Tomate'), findsOneWidget);
    expect(find.textContaining('tienda(s) cerca'), findsOneWidget);
    expect(find.byKey(const Key('copy_p1')), findsOneWidget);
  });
}
