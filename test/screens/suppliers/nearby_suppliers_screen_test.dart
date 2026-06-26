// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/suppliers/nearby_suppliers_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  static final _list = [
    {
      'id': 's1', 'business_name': '[SEED] El Tomate',
      'business_types': ['proveedor_agricola'],
      'distance_km': 0.71, 'product_count': 3, 'expiring_soon_count': 2,
      'lat': 4.345, 'lng': -74.365,
    },
    {
      'id': 's2', 'business_name': 'El Granero',
      'business_types': ['proveedor_mayorista'],
      'distance_km': 1.14, 'product_count': 3, 'expiring_soon_count': 0,
      'lat': 4.350, 'lng': -74.355,
    },
  ];

  @override
  Future<Map<String, dynamic>> fetchNearbySuppliersFull({double radiusKm = 5}) async =>
      {'data': _list, 'origin': {'lat': 4.341, 'lng': -74.360}};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('lista proveedores cercanos con distancia y badge por vencer', (tester) async {
    await tester.pumpWidget(MaterialApp(home: NearbySuppliersScreen(api: _FakeApi())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby_suppliers_list')), findsOneWidget);
    expect(find.text('El Tomate'), findsOneWidget); // sin el prefijo [SEED]
    expect(find.text('0.7 km'), findsOneWidget);
    expect(find.textContaining('por vencer'), findsOneWidget);
    expect(find.text('Agrícola'), findsOneWidget);
    expect(find.text('Mayorista'), findsOneWidget);
  });
}
