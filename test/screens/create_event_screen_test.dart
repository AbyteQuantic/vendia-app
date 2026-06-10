// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/event.dart';
import 'package:vendia_pos/screens/events/create_event_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  Map<String, dynamic>? createdBody;
  String? updatedId;
  Map<String, dynamic>? updatedBody;

  @override
  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> body) async {
    createdBody = body;
    return {...body, 'id': 'new-1', 'status': 'borrador'};
  }

  @override
  Future<Map<String, dynamic>> updateEvent(
      String id, Map<String, dynamic> body) async {
    updatedId = id;
    updatedBody = body;
    return {...body, 'id': id, 'status': 'publicado'};
  }
}

Widget _wrap(Widget c) => MaterialApp(home: c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('modo edición precarga los campos y hace PATCH', (tester) async {
    final api = _FakeApi();
    const existing = Event(
      id: 'e1',
      title: 'Curso de color',
      type: EventType.curso,
      modality: EventModality.presencial,
      price: 80000,
      currency: 'COP',
      capacity: 30,
    );
    await tester.pumpWidget(
        _wrap(CreateEventScreen(existing: existing, apiOverride: api)));
    await tester.pumpAndSettle();

    // El título de la pantalla refleja el modo edición y precarga el nombre.
    expect(find.text('Editar evento'), findsOneWidget);
    expect(find.text('Curso de color'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    // Cambia el cupo (desplazando hasta el campo) y guarda → PATCH.
    await tester.scrollUntilVisible(
        find.byKey(const Key('event_capacity')), 250,
        scrollable: scrollable);
    await tester.enterText(find.byKey(const Key('event_capacity')), '40');
    await tester.scrollUntilVisible(find.byKey(const Key('event_submit')), 250,
        scrollable: scrollable);
    expect(find.text('Guardar cambios'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.updatedId, 'e1');
    expect(api.createdBody, isNull);
    expect(api.updatedBody?['capacity'], 40);
    expect(api.updatedBody?['title'], 'Curso de color');
    expect(api.updatedBody?['currency'], 'COP');
  });
}
