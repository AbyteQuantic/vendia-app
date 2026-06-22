// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/task_center_controller.dart';
import 'package:vendia_pos/services/notification_toast_controller.dart';
import 'package:vendia_pos/widgets/notification_toast.dart';

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
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

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
}
