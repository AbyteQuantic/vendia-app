// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/events/events_list_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Minimal fake: controls what listEvents/createEvent return.
class _FakeApi extends ApiService {
  _FakeApi({this.events = const []}) : super(AuthService());

  final List<Map<String, dynamic>> events;

  @override
  Future<List<Map<String, dynamic>>> listEvents({String? status}) async =>
      events;
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('EventsListScreen (F042)', () {
    testWidgets('lista vacía → estado vacío + CTA, sin spinner', (tester) async {
      final api = _FakeApi(events: const []);
      await tester.pumpWidget(_wrap(EventsListScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Aún no tiene eventos'), findsOneWidget);
      // El FAB para crear siempre está disponible.
      expect(find.byKey(const Key('events_create_fab')), findsOneWidget);
    });

    testWidgets('con eventos → pinta título, estado y precio', (tester) async {
      final api = _FakeApi(events: [
        {
          'id': 'e1',
          'type': 'curso',
          'title': 'Curso de repostería',
          'modality': 'virtual',
          'status': 'publicado',
          'price': 50000,
          'capacity': 30,
        },
        {
          'id': 'e2',
          'type': 'hackaton',
          'title': 'Hackatón gratis',
          'modality': 'presencial',
          'status': 'borrador',
          'price': 0,
          'capacity': 0,
        },
      ]);
      await tester.pumpWidget(_wrap(EventsListScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      expect(find.text('Curso de repostería'), findsOneWidget);
      expect(find.text('Publicado'), findsOneWidget);
      expect(find.text('\$50000'), findsOneWidget);
      expect(find.text('Hackatón gratis'), findsOneWidget);
      expect(find.text('Gratis'), findsOneWidget);
      expect(find.text('Sin límite'), findsOneWidget);
    });
  });
}
