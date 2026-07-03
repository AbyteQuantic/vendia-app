// Spec: specs/012-cold-start-resiliencia/spec.md
//
// Concilio 2026-07-02: el fundador reportó que en señal débil el botón
// "Guardar Cambios" de Perfil del Negocio se quedaba en "Guardando..." de
// forma estática e indefinida (peor caso medido del interceptor de
// cold-start: ~4.7 min sin ninguna señal de progreso ni forma de cancelar —
// muy por encima de la ventana ~60-90s que specs/012 FR-05 promete: "la UI
// nunca queda colgada indefinidamente"). Este archivo cubre el fix: mensaje
// que evoluciona con el tiempo real transcurrido, botón Cancelar (aborta el
// request vía CancelToken), y un tope explícito con error accionable.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/dashboard/business_profile_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Fake ApiService — el perfil de fetch siempre resuelve rápido; el PATCH de
/// guardado se controla por [neverResolves] para simular una conexión que
/// nunca responde (el escenario real reportado: señal débil, el request
/// jamás llega al backend).
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  bool neverResolves = false;
  int updateCallCount = 0;
  CancelToken? lastCancelToken;

  @override
  Future<Map<String, dynamic>> fetchBusinessProfile() async => {
        'business_name': 'Tienda Test',
        'business_types': ['tienda_barrio'],
      };

  @override
  Future<Map<String, dynamic>> updateBusinessProfile(
    Map<String, dynamic> data, {
    CancelToken? cancelToken,
  }) {
    updateCallCount++;
    lastCancelToken = cancelToken;
    if (!neverResolves) {
      return Future<Map<String, dynamic>>.value({'message': 'ok'});
    }
    final completer = Completer<Map<String, dynamic>>();
    cancelToken?.whenCancel.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          DioException(
            requestOptions: RequestOptions(path: '/api/v1/store/profile'),
            type: DioExceptionType.cancel,
          ),
        );
      }
    });
    return completer.future;
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? null : <String, String>{},
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  testWidgets(
      'mensaje estático "Guardando..." en los primeros segundos, sin botón '
      'Cancelar todavía', (tester) async {
    final api = _FakeApi()..neverResolves = true;
    await tester.pumpWidget(_wrap(BusinessProfileScreen(apiOverride: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar Cambios'));
    await tester.pump();

    expect(find.byKey(const Key('save_status_message')), findsOneWidget);
    expect(find.text('Guardando...'), findsWidgets);
    expect(find.byKey(const Key('btn_cancel_save')), findsNothing);

    // Limpieza: liquida el request pendiente para no dejar el Timer del
    // `.timeout()` colgado al final del test (fakeAsync exige cero timers
    // pendientes al terminar).
    api.lastCancelToken?.cancel();
    await tester.pump();
  });

  testWidgets(
      'tras 5s el mensaje avisa señal débil y aparece el botón Cancelar '
      '(FR-05 — nunca colgado sin señal)', (tester) async {
    final api = _FakeApi()..neverResolves = true;
    await tester.pumpWidget(_wrap(BusinessProfileScreen(apiOverride: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar Cambios'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Seguimos intentando, la señal está débil...'),
        findsOneWidget);
    expect(find.byKey(const Key('btn_cancel_save')), findsOneWidget);

    api.lastCancelToken?.cancel();
    await tester.pump();
  });

  testWidgets('tras 20s el mensaje escala a "tardando más de lo normal"',
      (tester) async {
    final api = _FakeApi()..neverResolves = true;
    await tester.pumpWidget(_wrap(BusinessProfileScreen(apiOverride: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar Cambios'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));

    expect(
        find.text('Esto está tardando más de lo normal...'), findsOneWidget);

    api.lastCancelToken?.cancel();
    await tester.pump();
  });

  testWidgets(
      'tocar Cancelar aborta el request (CancelToken) y muestra snack '
      'neutral, sin quedar en "Guardando..."', (tester) async {
    final api = _FakeApi()..neverResolves = true;
    await tester.pumpWidget(_wrap(BusinessProfileScreen(apiOverride: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar Cambios'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(api.lastCancelToken!.isCancelled, isFalse);

    await tester.tap(find.byKey(const Key('btn_cancel_save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.lastCancelToken!.isCancelled, isTrue);
    expect(find.text('Guardado cancelado.'), findsOneWidget);
    // El botón vuelve a su estado normal — no queda "Guardando..." colgado.
    expect(find.text('Guardar Cambios'), findsOneWidget);
    expect(find.byKey(const Key('save_status_message')), findsNothing);
  });

  testWidgets(
      'tope explícito: si el request nunca resuelve, tras el tope se '
      'cancela solo y muestra el error accionable (nunca queda colgado '
      'para siempre)', (tester) async {
    final api = _FakeApi()..neverResolves = true;
    await tester.pumpWidget(_wrap(BusinessProfileScreen(apiOverride: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar Cambios'));
    await tester.pump();
    // Avanza más allá del tope duro (85s) en un solo salto.
    await tester.pump(const Duration(seconds: 86));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text(
          'No pudimos guardar. Verifique su conexión e intente de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Guardar Cambios'), findsOneWidget);
  });

  testWidgets('guardado exitoso (rápido) no muestra fila de estado ni '
      'Cancelar', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(BusinessProfileScreen(apiOverride: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar Cambios'));
    await tester.pumpAndSettle();

    expect(api.updateCallCount, 1);
    expect(find.byKey(const Key('save_status_message')), findsNothing);
    expect(find.byKey(const Key('btn_cancel_save')), findsNothing);
  });
}
