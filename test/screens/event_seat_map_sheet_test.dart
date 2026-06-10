// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/event.dart';
import 'package:vendia_pos/screens/events/event_seat_map_sheet.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  String? lastRegId;
  int? lastSeat;

  @override
  Future<Map<String, dynamic>> assignEventSeat(
      String eventId, String regId, int? seat) async {
    lastRegId = regId;
    lastSeat = seat;
    return {'id': regId, 'seat_number': seat};
  }
}

Widget _wrap(Widget c) => MaterialApp(home: c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('pinta una silla por cupo y marca la asignada con su asistente',
      (tester) async {
    final regs = [
      const EventRegistrationView(
          id: 'r1', customerName: 'Ana Pérez', seatNumber: 2),
      const EventRegistrationView(id: 'r2', customerName: 'Beto Díaz'),
    ];
    await tester.pumpWidget(_wrap(EventSeatMapSheet(
      eventId: 'e1',
      capacity: 4,
      registrations: regs,
      apiOverride: _FakeApi(),
    )));
    await tester.pumpAndSettle();

    // 4 sillas (1..4) + el contador "1/4 asignadas".
    expect(find.text('1/4 asignadas'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget); // primer nombre en la silla 2
    // Hay 4 íconos de silla en la grilla.
    expect(find.byIcon(Icons.event_seat_rounded), findsNWidgets(4));
  });

  testWidgets('el buscador resalta por nombre (atenúa las no coincidentes)',
      (tester) async {
    final regs = [
      const EventRegistrationView(
          id: 'r1', customerName: 'Ana Pérez', seatNumber: 1),
    ];
    await tester.pumpWidget(_wrap(EventSeatMapSheet(
      eventId: 'e1',
      capacity: 3,
      registrations: regs,
      apiOverride: _FakeApi(),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ana');
    await tester.pump();
    // El nombre sigue visible (su silla coincide con el filtro).
    expect(find.text('Ana'), findsOneWidget);
  });
}
