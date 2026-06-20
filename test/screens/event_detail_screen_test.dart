// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/event.dart';
import 'package:vendia_pos/screens/events/event_detail_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.regs = const []}) : super(AuthService());

  final List<Map<String, dynamic>> regs;
  String? certifiedRegId;
  String? cancelledEventId;

  @override
  Future<Map<String, dynamic>> cancelEvent(String id) async {
    cancelledEventId = id;
    return {'id': id, 'status': 'cancelado'};
  }

  @override
  Future<List<Map<String, dynamic>>> listEventRegistrations(String id) async =>
      regs;

  @override
  Future<List<Map<String, dynamic>>> listEventPayments(String eventId,
          {String status = 'pending'}) async =>
      const [];

  @override
  Future<Map<String, dynamic>> fetchStoreConfig() async => const {
        'store_slug': 'mi-tienda',
        'enable_promotions': false,
      };

  @override
  Future<void> issueEventCertificate(String eventId, String regId) async {
    certifiedRegId = regId;
  }
}

Widget _wrap(Widget c) => MaterialApp(home: c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  const ev = Event(
    id: 'e1',
    title: 'Curso',
    type: EventType.curso,
    modality: EventModality.virtual,
    status: EventStatus.publicado,
    price: 50000,
    capacity: 10,
  );

  testWidgets('panel pinta inscritos con estado de pago y asistencia',
      (tester) async {
    final api = _FakeApi(regs: [
      {
        'id': 'r1',
        'customer_name': 'Ana',
        'customer_phone': '3001234567',
        'payment_status': 'confirmed',
        'checked_in': true,
        'checked_out': false,
        'certificate_eligible': false,
      },
    ]);
    await tester.pumpWidget(_wrap(EventDetailScreen(event: ev, apiOverride: api)));
    await tester.pumpAndSettle();

    // La lista de inscritos vive al final del detalle (tras hero + tarjetas);
    // hay que desplazar para que el ListView construya esas filas.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Ana'), 300, scrollable: scrollable);

    expect(find.text('Ana'), findsOneWidget);
    // Inscripción confirmada → carné activo (sin saldo pendiente).
    expect(find.textContaining('Carné activo'), findsOneWidget);
    expect(find.textContaining('Entró'), findsOneWidget);
    expect(find.textContaining('1 confirmados'), findsOneWidget);
  });

  testWidgets('asistente elegible muestra "Emitir certificado" y lo emite',
      (tester) async {
    final api = _FakeApi(regs: [
      {
        'id': 'r2',
        'customer_name': 'Beto',
        'payment_status': 'confirmed',
        'certificate_eligible': true,
        'certificate_issued': false,
      },
    ]);
    await tester.pumpWidget(_wrap(EventDetailScreen(event: ev, apiOverride: api)));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Emitir certificado'), 300,
        scrollable: scrollable);
    await tester.pumpAndSettle();

    final btn = find.text('Emitir certificado');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();
    await tester.tap(btn);
    await tester.pump();
    expect(api.certifiedRegId, 'r2');
  });

  testWidgets('sin overflow a 360dp (Art. I) tras el refactor UI', (tester) async {
    // Lienzo angosto tipo Android de gama baja. Si algún Row/botón del
    // rediseño no cabe, Flutter lanza un RenderFlex overflow y este test
    // falla vía tester.takeException().
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi(regs: [
      {
        'id': 'r3',
        'customer_name': 'Carolina Restrepo de la Espriella',
        'customer_phone': '3001234567',
        'payment_status': 'pending',
        'amount_paid': 20000,
        'checked_in': true,
        'checked_out': true,
        'certificate_eligible': true,
        'certificate_issued': true,
        'seat_number': 12,
      },
    ]);
    await tester.pumpWidget(_wrap(EventDetailScreen(event: ev, apiOverride: api)));
    await tester.pumpAndSettle();

    // Recorre toda la pantalla para forzar el layout de cada sección.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
        find.textContaining('Carolina'), 300, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // Spec 069 — un evento publicado expone Finalizar/Cancelar; Cancelar (con
  // confirmación) llama a la API y saca el evento del catálogo.
  testWidgets('publicado expone Finalizar/Cancelar y Cancelar llama a la API',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(EventDetailScreen(event: ev, apiOverride: api)));
    await tester.pumpAndSettle();

    final cancelBtn = find.byKey(const Key('detail_cancel_event'));
    await tester.scrollUntilVisible(cancelBtn, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail_finish_event')), findsOneWidget);

    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();
    // Diálogo de confirmación → confirmar.
    await tester.tap(find.text('Cancelar evento').last);
    await tester.pumpAndSettle();

    expect(api.cancelledEventId, 'e1');
  });
}
