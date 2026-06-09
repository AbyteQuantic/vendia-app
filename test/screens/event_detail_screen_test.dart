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

  @override
  Future<List<Map<String, dynamic>>> listEventRegistrations(String id) async =>
      regs;

  @override
  Future<List<Map<String, dynamic>>> listEventPayments(String eventId,
          {String status = 'pending'}) async =>
      const [];

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

    final btn = find.text('Emitir certificado');
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(api.certifiedRegId, 'r2');
  });
}
