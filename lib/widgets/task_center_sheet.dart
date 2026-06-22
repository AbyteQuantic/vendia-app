// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../models/app_notification.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/task_center_controller.dart';
import '../screens/online_orders/online_orders_screen.dart';
import '../screens/mandados/mandados_screen.dart';
import '../screens/recipes/recipes_home_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';
import '../utils/format_cop.dart';

/// openTaskCenter — PUNTO DE ENTRADA ÚNICO al Centro de Tareas (Dashboard y POS).
/// Arranca el poller, abre el Centro y navega a la pantalla dueña al tocar una
/// tarea (centraliza la navegación para no duplicarla). Spec 078.
Future<void> openTaskCenter(BuildContext context) async {
  try {
    context.read<TaskCenterController>().start();
  } catch (_) {}
  if (!context.mounted) return;
  // navigateToTask revalida context.mounted antes de navegar.
  // ignore: use_build_context_synchronously
  await showTaskCenter(context, onOpenTask: (t) => navigateToTask(context, t));
}

/// navigateToTask — abre la pantalla dueña de la tarea; al volver, refresca.
void navigateToTask(BuildContext context, Task t) {
  if (!context.mounted) return;
  Widget? screen;
  switch (t.kind) {
    case 'online_order':
    case 'table_account':
      screen = const OnlineOrdersScreen();
      break;
    case 'errand':
    case 'reorder':
      screen = const MandadosScreen();
      break;
    case 'menu_incomplete':
      screen = const RecipesHomeScreen();
      break;
    default:
      screen = null; // perishable/otros: refinado luego
  }
  if (screen == null) return;
  final s = screen;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => s)).then((_) {
    if (!context.mounted) return;
    try {
      context.read<TaskCenterController>().refresh();
    } catch (_) {}
  });
}

/// showTaskCenter — el ÚNICO Centro de Tareas y Notificaciones. Reemplaza las dos
/// superficies dispersas (campana del Dashboard + feed del POS). Dos pestañas:
/// "Por hacer" (tareas accionables agrupadas por urgencia, con acción inline y
/// posponer) y "Novedades" (la bandeja de eventos/avisos). Spec 078, Fase 2-3.
/// [onOpenTask] lo provee el host para navegar a la pantalla dueña.
Future<void> showTaskCenter(
  BuildContext context, {
  required void Function(Task task) onOpenTask,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _TaskCenter(scroll: scroll, onOpenTask: onOpenTask),
    ),
  );
}

class _TaskCenter extends StatefulWidget {
  const _TaskCenter({required this.scroll, required this.onOpenTask});
  final ScrollController scroll;
  final void Function(Task) onOpenTask;

  @override
  State<_TaskCenter> createState() => _TaskCenterState();
}

class _TaskCenterState extends State<_TaskCenter> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int open = 0;
    try {
      open = context.watch<TaskCenterController>().openCount;
    } catch (_) {}
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppUI.s8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppUI.border, borderRadius: BorderRadius.circular(2))),
        TabBar(
          controller: _tabs,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppUI.inkSoft,
          indicatorColor: AppTheme.primary,
          tabs: [
            Tab(text: open > 0 ? 'Por hacer ($open)' : 'Por hacer'),
            const Tab(text: 'Novedades'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _TaskCenterBody(scroll: widget.scroll, onOpenTask: widget.onOpenTask),
              const _NovedadesTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bucket {
  final String label;
  final bool Function(Task) match;
  const _Bucket(this.label, this.match);
}

final List<_Bucket> _buckets = [
  _Bucket('Ahora', (t) => t.urgency == 'critical'),
  _Bucket('Hoy', (t) => t.urgency == 'high'),
  _Bucket('Esta semana', (t) => t.urgency == 'normal'),
  _Bucket('Más adelante', (t) => t.urgency == 'low'),
];

class _TaskCenterBody extends StatelessWidget {
  const _TaskCenterBody({required this.scroll, required this.onOpenTask});
  final ScrollController scroll;
  final void Function(Task) onOpenTask;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<TaskCenterController>();
    final tasks = ctrl.tasks;
    if (tasks.isEmpty) return const _AllDone();
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s24),
      children: [
        for (final b in _buckets) ..._section(context, b.label, tasks.where(b.match).toList(), ctrl),
      ],
    );
  }

  List<Widget> _section(BuildContext context, String label, List<Task> items, TaskCenterController ctrl) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: AppUI.s16, bottom: AppUI.s8),
        child: Text(label.toUpperCase(),
            style: AppUI.bodySoft.copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ),
      ...items.map((t) => _TaskCard(task: t, onOpen: () => _open(context, t), onSnooze: t.isDismissable ? () => ctrl.dismiss(t.id) : null)),
    ];
  }

  void _open(BuildContext context, Task t) {
    // Navegar a la pantalla dueña; al resolver allí, el próximo fetch (o el
    // refresh al volver) quita la tarea. No marcamos optimista por solo abrir.
    Navigator.pop(context);
    onOpenTask(t);
  }
}

Color _urgencyColor(String u) {
  switch (u) {
    case 'critical':
      return AppTheme.error;
    case 'high':
      return AppTheme.warning;
    case 'normal':
      return AppTheme.primary;
    default:
      return AppUI.inkSoft;
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onOpen, this.onSnooze});
  final Task task;
  final VoidCallback onOpen;
  final VoidCallback? onSnooze;

  @override
  Widget build(BuildContext context) {
    final color = _urgencyColor(task.urgency);
    return Container(
      key: Key('task_${task.id}'),
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppUI.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6, right: AppUI.s12),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodyStrong)),
              if (task.amount > 0) ...[
                const SizedBox(width: AppUI.s8),
                Text(formatCOP(task.amount),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ],
            ]),
            if (task.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(task.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppUI.bodySoft),
            ],
            const SizedBox(height: AppUI.s8),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    key: Key('task_action_${task.id}'),
                    onPressed: onOpen,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: color, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: Text(task.actionLabel.isEmpty ? 'Abrir' : task.actionLabel),
                  ),
                ),
              ),
              if (onSnooze != null) ...[
                const SizedBox(width: AppUI.s8),
                TextButton(
                  key: Key('task_snooze_${task.id}'),
                  onPressed: onSnooze,
                  child: const Text('Más tarde'),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// _NovedadesTab — la bandeja de eventos/avisos (tabla Notification): fiado,
/// pagos, recordatorios. Coexiste con las tareas; se marca leída al abrir.
class _NovedadesTab extends StatefulWidget {
  const _NovedadesTab();
  @override
  State<_NovedadesTab> createState() => _NovedadesTabState();
}

class _NovedadesTabState extends State<_NovedadesTab> {
  ApiService? _api;
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    try {
      _api = ApiService(AuthService());
    } catch (_) {
      _api = null; // tests sin dotenv/keychain
    }
    _future = _load();
  }

  Future<List<AppNotification>> _load() async {
    final api = _api;
    if (api == null) return const [];
    try {
      final res = await api.fetchNotifications();
      final list = ((res['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final parsed = list.map(AppNotification.fromApi).whereType<AppNotification>().toList();
      // Marca leídas (al abrir Novedades el tendero ya las vio).
      api.markNotificationsRead().catchError((_) {});
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppNotification>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(AppUI.s24), child: CircularProgressIndicator()));
        }
        final items = snap.data ?? const <AppNotification>[];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppUI.s24),
              child: Text('Sin novedades por ahora.', style: AppUI.bodySoft),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppUI.s16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
          itemBuilder: (_, i) {
            final n = items[i];
            return Container(
              padding: const EdgeInsets.all(AppUI.s12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppUI.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: AppUI.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(n.body, style: AppUI.bodySoft, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ]),
            );
          },
        );
      },
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('☕', style: TextStyle(fontSize: 44)),
        SizedBox(height: AppUI.s12),
        Text('Todo al día, ¡bien hecho!', style: AppUI.bodyStrong),
        SizedBox(height: 4),
        Text('No tiene pendientes por ahora.', style: AppUI.bodySoft),
      ]),
    );
  }
}
