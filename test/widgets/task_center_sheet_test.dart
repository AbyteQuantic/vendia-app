// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/task_center_controller.dart';
import 'package:vendia_pos/models/task.dart';
import 'package:vendia_pos/widgets/task_center_sheet.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  List<Map<String, dynamic>> next = [];
  List<String> dismissed = [];
  @override
  Future<({List<Map<String, dynamic>> tasks, Map<String, dynamic> counts})> fetchTasks(
          {String branchId = ''}) async =>
      (tasks: next, counts: {'actionable': next.length});
  @override
  Future<void> dismissTask(String taskId, {int hours = 24}) async => dismissed.add(taskId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  Future<void> pumpSheet(WidgetTester tester, TaskCenterController c, {List<Task> opened = const []}) async {
    final openedList = <Task>[];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: c,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTaskCenter(ctx, onOpenTask: openedList.add),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('agrupa por urgencia y muestra una tarjeta por tarea', (tester) async {
    final api = _FakeApi();
    api.next = [
      {'id': 'table_account:1', 'kind': 'table_account', 'urgency': 'critical', 'title': 'Mesa 3', 'subtitle': 'Lista para cobrar', 'action_label': 'Cobrar', 'amount': 18000},
      {'id': 'reorder:t', 'kind': 'reorder', 'urgency': 'normal', 'title': 'Productos por reordenar', 'action_label': 'Reordenar'},
    ];
    final c = TaskCenterController(api);
    await c.refresh();
    await pumpSheet(tester, c);

    expect(find.text('AHORA'), findsOneWidget);
    expect(find.text('Mesa 3'), findsOneWidget);
    expect(find.text('Cobrar'), findsOneWidget);
    expect(find.text('Productos por reordenar'), findsOneWidget);
    // La agregada tiene "Más tarde" (posponer); la mesa no.
    expect(find.byKey(const Key('task_snooze_reorder:t')), findsOneWidget);
    expect(find.byKey(const Key('task_snooze_table_account:1')), findsNothing);
  });

  testWidgets('reorder_out (agotados) también es posponible', (tester) async {
    final api = _FakeApi();
    api.next = [
      {'id': 'reorder_out:t', 'kind': 'reorder_out', 'urgency': 'high', 'title': 'Productos agotados', 'action_label': 'Reordenar'},
    ];
    final c = TaskCenterController(api);
    await c.refresh();
    await pumpSheet(tester, c);

    expect(find.text('Productos agotados'), findsOneWidget);
    expect(find.byKey(const Key('task_snooze_reorder_out:t')), findsOneWidget);
  });

  testWidgets('posponer una agregada llama al API', (tester) async {
    final api = _FakeApi();
    api.next = [
      {'id': 'perishable:t', 'kind': 'perishable', 'urgency': 'normal', 'title': 'Por vencer', 'action_label': 'Crear promoción'},
    ];
    final c = TaskCenterController(api);
    await c.refresh();
    await pumpSheet(tester, c);

    await tester.tap(find.byKey(const Key('task_snooze_perishable:t')));
    await tester.pumpAndSettle();
    expect(api.dismissed, contains('perishable:t'));
  });

  testWidgets('estado vacío motivador', (tester) async {
    final api = _FakeApi();
    final c = TaskCenterController(api);
    await c.refresh();
    await pumpSheet(tester, c);
    expect(find.textContaining('Todo al día'), findsOneWidget);
  });
}
