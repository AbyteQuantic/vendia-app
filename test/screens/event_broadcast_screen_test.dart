// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vendia_pos/models/event.dart';
import 'package:vendia_pos/screens/events/event_broadcast_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.customers = const []}) : super(AuthService());
  final List<Map<String, dynamic>> customers;

  @override
  Future<Map<String, dynamic>> fetchCustomers({
    int page = 1,
    int perPage = 20,
  }) async =>
      {'data': customers};
}

Widget _wrap(Widget c) => MaterialApp(home: c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'vendia_business_name': 'Tienda Ana',
      'vendia_store_slug': 'tienda-ana',
    });
    return dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  const ev = Event(
    id: 'e1',
    title: 'Curso de color',
    type: EventType.curso,
    modality: EventModality.presencial,
    price: 50000,
    currency: 'COP',
  );

  testWidgets('lista clientes con consentimiento y muestra el mensaje',
      (tester) async {
    final api = _FakeApi(customers: [
      {'id': 'c1', 'name': 'Ana', 'phone': '3001234567', 'marketing_opt_in': true},
      {'id': 'c2', 'name': 'Beto', 'phone': '3009999999', 'marketing_opt_in': false},
    ]);
    await tester.pumpWidget(_wrap(
        EventBroadcastScreen(event: ev, slug: 'tienda-ana', apiOverride: api)));
    await tester.pumpAndSettle();

    // Arriba: el mensaje incluye el evento y el link, y las opciones de redes.
    expect(find.textContaining('Curso de color'), findsWidgets);
    expect(find.textContaining('tienda-ana'), findsWidgets);
    expect(find.text('Compartir en redes'), findsOneWidget);

    // La lista de clientes vive más abajo (ListView perezoso) → desplazar.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Ana'), 250, scrollable: scrollable);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Enviar a mis clientes (1)'), findsOneWidget);
    // El cliente sin consentimiento queda fuera.
    expect(find.text('Beto'), findsNothing);
  });

  testWidgets('sin clientes con consentimiento muestra estado vacío',
      (tester) async {
    final api = _FakeApi(customers: const []);
    await tester.pumpWidget(_wrap(
        EventBroadcastScreen(event: ev, slug: 'tienda-ana', apiOverride: api)));
    await tester.pumpAndSettle();

    // Las opciones de redes sociales siguen disponibles (arriba).
    expect(find.text('Compartir en redes'), findsOneWidget);
    expect(find.byKey(const Key('social_whatsapp')), findsOneWidget);
    expect(find.byKey(const Key('social_more')), findsOneWidget);
    // El encabezado (0) vive más abajo → desplazar.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
        find.text('Enviar a mis clientes (0)'), 250, scrollable: scrollable);
    expect(find.text('Enviar a mis clientes (0)'), findsOneWidget);
  });
}
