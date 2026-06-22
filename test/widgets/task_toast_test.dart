// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/task_center_controller.dart';
import 'package:vendia_pos/services/notification_toast_controller.dart';
import 'package:vendia_pos/widgets/notification_toast.dart';
import 'package:vendia_pos/widgets/draggable_toast_host.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._tasks) : super(AuthService());
  final List<Map<String, dynamic>> _tasks;
  @override
  Future<({List<Map<String, dynamic>> tasks, Map<String, dynamic> counts})> fetchTasks(
          {String branchId = ''}) async =>
      (tasks: _tasks, counts: <String, dynamic>{});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'); SharedPreferences.setMockInitialValues({}); });

  testWidgets('una tarea urgente se muestra como toast con CTA', (tester) async {
    final tc = TaskCenterController(_FakeApi([
      {'id': 'online_order:1', 'kind': 'online_order', 'urgency': 'critical',
       'title': 'Pedido en línea de Ana', 'subtitle': 'por aceptar', 'action_label': 'Aceptar'},
    ]));
    await tc.refresh();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: tc),
        ChangeNotifierProvider(create: (_) => NotificationToastController()),
      ],
      child: const MaterialApp(home: Scaffold(body: NotificationToast())),
    ));
    await tester.pump();

    expect(find.byKey(const Key('task_toast')), findsOneWidget);
    expect(find.text('Pedido en línea de Ana'), findsOneWidget);
    expect(find.byKey(const Key('task_toast_cta')), findsOneWidget);

    // Cerrar → ya no interrumpe.
    await tester.tap(find.byKey(const Key('task_toast_close')));
    await tester.pump();
    expect(find.byKey(const Key('task_toast')), findsNothing);
  });

  testWidgets('sin tareas urgentes no se muestra el toast de tarea', (tester) async {
    final tc = TaskCenterController(_FakeApi([
      {'id': 'reorder:t', 'kind': 'reorder', 'urgency': 'normal', 'title': 'Reordenar'},
    ]));
    await tc.refresh();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: tc),
        ChangeNotifierProvider(create: (_) => NotificationToastController()),
      ],
      child: const MaterialApp(home: Scaffold(body: NotificationToast())),
    ));
    await tester.pump();
    expect(find.byKey(const Key('task_toast')), findsNothing);
  });

  testWidgets('DraggableToastHost muestra el toast y se puede arrastrar', (tester) async {
    final tc = TaskCenterController(_FakeApi([
      {'id': 'online_order:1', 'kind': 'online_order', 'urgency': 'critical',
       'title': 'Pedido de Ana', 'action_label': 'Aceptar'},
    ]));
    await tc.refresh();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: tc),
        ChangeNotifierProvider(create: (_) => NotificationToastController()),
      ],
      child: const MaterialApp(home: Scaffold(body: Stack(children: [DraggableToastHost()]))),
    ));
    await tester.pump();
    expect(find.byKey(const Key('task_toast')), findsOneWidget);

    // Arrastrar el toast hacia abajo no lo rompe y sigue visible.
    await tester.drag(find.byKey(const Key('task_toast')), const Offset(0, 120));
    await tester.pump();
    expect(find.byKey(const Key('task_toast')), findsOneWidget);
  });

  testWidgets('el toast se auto-colapsa a pastilla y se expande al tocar', (tester) async {
    final tc = TaskCenterController(_FakeApi([
      {'id': 'online_order:9', 'kind': 'online_order', 'urgency': 'critical', 'title': 'Pedido', 'action_label': 'Aceptar'},
    ]));
    await tc.refresh();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: tc),
        ChangeNotifierProvider(create: (_) => NotificationToastController()),
      ],
      child: const MaterialApp(home: Scaffold(body: Stack(children: [DraggableToastHost()]))),
    ));
    await tester.pump();
    expect(find.byKey(const Key('task_toast')), findsOneWidget);
    // pasa el tiempo → colapsa a pastilla.
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const Key('task_toast')), findsNothing);
    expect(find.byKey(const Key('toast_pill')), findsOneWidget);
    // tocar la pastilla → se expande de nuevo.
    await tester.tap(find.byKey(const Key('toast_pill')));
    await tester.pump();
    expect(find.byKey(const Key('task_toast')), findsOneWidget);
  });
}
