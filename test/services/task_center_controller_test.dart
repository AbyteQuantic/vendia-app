// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/task_center_controller.dart';

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

Map<String, dynamic> _t(String id, String urgency) =>
    {'id': id, 'kind': id.split(':').first, 'urgency': urgency, 'title': id, 'action_label': 'X'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  test('openCount cuenta solo accionables; hasUrgent detecta crítico', () async {
    final api = _FakeApi();
    api.next = [
      _t('table_account:1', 'critical'),
      _t('reorder:t', 'normal'),
      _t('rotation:x', 'low'), // informativa → NO cuenta
    ];
    final c = TaskCenterController(api);
    await c.refresh();
    expect(c.tasks.length, 3);
    expect(c.openCount, 2); // critical + normal
    expect(c.hasUrgent, true);
  });

  test('resolveLocally oculta de inmediato y se limpia cuando el server confirma', () async {
    final api = _FakeApi();
    api.next = [_t('online_order:1', 'critical')];
    final c = TaskCenterController(api);
    await c.refresh();
    expect(c.openCount, 1);

    c.resolveLocally('online_order:1'); // optimista
    expect(c.tasks.where((t) => t.id == 'online_order:1'), isEmpty);

    api.next = []; // el server ya no la trae (resuelta de verdad)
    await c.refresh();
    expect(c.tasks, isEmpty);
  });

  test('toastCandidate = la urgente; dismissToast no vuelve a interrumpir', () async {
    final api = _FakeApi();
    api.next = [
      _t('reorder:t', 'normal'), // no urgente → no toast
      _t('online_order:1', 'critical'),
    ];
    final c = TaskCenterController(api);
    await c.refresh();
    expect(c.toastCandidate?.id, 'online_order:1'); // solo lo urgente
    c.dismissToast();
    expect(c.toastCandidate, isNull); // cerrada → no reaparece
  });

  test('dismiss llama al API y oculta la tarea agregada', () async {
    final api = _FakeApi();
    api.next = [_t('reorder:t', 'normal')];
    final c = TaskCenterController(api);
    await c.refresh();
    api.next = []; // tras posponer, el server la excluye
    await c.dismiss('reorder:t');
    expect(api.dismissed, contains('reorder:t'));
    expect(c.tasks, isEmpty);
  });
}
