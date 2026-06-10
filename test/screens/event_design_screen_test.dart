// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/events/event_design_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  int badgeCalls = 0;

  @override
  Future<String> generateEventBadge(String eventId, {String? brief}) async {
    badgeCalls++;
    // data URL para que el preview use Image.memory (sin red en test).
    return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
  }
}

Widget _wrap(Widget c) => MaterialApp(home: c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('estado vacío → "Generar con IA"; tras generar → preview + "Usar"',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(EventDesignScreen(
      eventId: 'e1',
      kind: EventDesignKind.badge,
      apiOverride: api,
    )));
    await tester.pump();

    // Estado vacío: botón "Generar con IA", sin "Usar este diseño".
    expect(find.text('Generar con IA'), findsOneWidget);
    expect(find.byKey(const Key('design_use')), findsNothing);

    await tester.tap(find.byKey(const Key('design_generate')));
    await tester.pump(); // dispara generación
    await tester.pump(const Duration(milliseconds: 50)); // resuelve future

    expect(api.badgeCalls, 1);
    // Ahora hay preview → aparece "Usar este diseño", "Generar otra" y
    // "Mejorar con IA" (retoca la imagen actual).
    expect(find.byKey(const Key('design_use')), findsOneWidget);
    expect(find.text('Generar otra'), findsOneWidget);
    expect(find.byKey(const Key('design_enhance')), findsOneWidget);
    expect(find.text('Mejorar con IA'), findsOneWidget);
  });

  testWidgets('ofrece ambos caminos: generar con IA y subir imagen propia',
      (tester) async {
    await tester.pumpWidget(_wrap(EventDesignScreen(
      eventId: 'e1',
      kind: EventDesignKind.poster,
      apiOverride: _FakeApi(),
    )));
    await tester.pump();

    // El tenant ve las dos opciones desde el estado vacío.
    expect(find.byKey(const Key('design_generate')), findsOneWidget);
    expect(find.byKey(const Key('design_upload')), findsOneWidget);
    expect(find.text('Subir mi imagen'), findsOneWidget);
  });

  testWidgets('campo de indicaciones visible y precargado con la descripción',
      (tester) async {
    await tester.pumpWidget(_wrap(EventDesignScreen(
      eventId: 'e1',
      kind: EventDesignKind.poster,
      initialBrief: 'Curso de repostería para principiantes',
      apiOverride: _FakeApi(),
    )));
    await tester.pump();

    final brief = find.byKey(const Key('design_brief'));
    expect(brief, findsOneWidget);
    // Precargado con la descripción del evento para no partir de cero.
    expect(find.text('Curso de repostería para principiantes'), findsOneWidget);
  });

  testWidgets('"Usar este diseño" cierra devolviendo la URL', (tester) async {
    final api = _FakeApi();
    String? popped;
    await tester.pumpWidget(_wrap(Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () async {
          popped = await Navigator.of(ctx).push<String>(MaterialPageRoute(
            builder: (_) => EventDesignScreen(
              eventId: 'e1',
              kind: EventDesignKind.badge,
              apiOverride: api,
            ),
          ));
        },
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('design_generate')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('design_use')));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.startsWith('data:image'), isTrue);
  });
}
