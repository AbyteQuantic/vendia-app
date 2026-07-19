// Spec: specs/078-centro-tareas-unificado/spec.md
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/task.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// TaskCenterController — el ÚNICO origen de tareas/notificaciones de la app.
/// Un solo Timer.periodic(15s) reemplaza los dos pollers anteriores
/// (OnlineOrdersBell + feed del POS). Deduplica, ordena por urgencia y mantiene
/// resoluciones optimistas anti-flicker. Spec 078, Fase 1.
class TaskCenterController extends ChangeNotifier {
  TaskCenterController(this._api);
  final ApiService _api;

  static const _pollInterval = Duration(seconds: 15);

  List<Task> _tasks = const [];
  Map<String, dynamic> _counts = const {};
  bool _loading = false;
  Timer? _timer;
  String _branchId = '';

  // Resoluciones locales (optimistas): ids que el usuario acaba de resolver y que
  // se ocultan hasta que el server confirme que ya no vienen (anti-flicker).
  final Set<String> _locallyResolved = {};

  // Toasts ya cerrados por el usuario: una tarea urgente interrumpe UNA vez.
  final Set<String> _toastDismissed = {};

  List<Task> get tasks =>
      _tasks.where((t) => !_locallyResolved.contains(t.id)).toList(growable: false);
  bool get loading => _loading;

  /// Cuenta solo lo ACCIONABLE (urgente+importante) — lo que va en el badge.
  int get openCount => tasks.where((t) => t.isActionable).length;

  /// Hay al menos una tarea urgente (badge rojo).
  bool get hasUrgent => tasks.any((t) => t.isUrgent);

  /// La tarea URGENTE (critical/high) más prioritaria que el usuario no haya
  /// cerrado en el toast. null = no interrumpir. Solo lo urgente interrumpe, y
  /// una sola vez (Spec 078 F3 — regla anti-ruido).
  Task? get toastCandidate {
    for (final t in tasks) {
      if (t.isUrgent && !_toastDismissed.contains(t.id)) return t;
    }
    return null;
  }

  /// Cierra el toast de tareas (no vuelve a interrumpir con esa tarea).
  void dismissToast() {
    final c = toastCandidate;
    if (c == null) return;
    _toastDismissed.add(c.id);
    notifyListeners();
  }

  /// Arranca el polling único (idempotente). Llamar una vez sobre el MaterialApp.
  void start({String branchId = ''}) {
    _branchId = branchId;
    _timer ??= Timer.periodic(_pollInterval, (_) => refresh());
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setBranch(String branchId) {
    if (branchId == _branchId) return;
    _branchId = branchId;
    refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    // Hotfix bucle "sesión expiró" (2026-07-19): sin sesión no hay tareas
    // que pedir — el Timer.periodic quedaba vivo tras el logout y seguía
    // golpeando la API (401) cada 15s sobre la pantalla de Login.
    if (!await AuthService().hasSession()) {
      stop();
      return;
    }
    _loading = true;
    try {
      final res = await _api.fetchTasks(branchId: _branchId);
      _tasks = res.tasks.map(Task.fromJson).toList();
      _counts = res.counts;
      // Limpia resoluciones locales ya confirmadas por el server (ya no vienen).
      final present = _tasks.map((t) => t.id).toSet();
      _locallyResolved.removeWhere((id) => !present.contains(id));
      _toastDismissed.removeWhere((id) => !present.contains(id));
    } catch (_) {
      // best-effort: mantiene el último snapshot; el centro nunca se cae por red.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Oculta una tarea recién resuelta de inmediato (antes del próximo fetch).
  /// Si el server sigue trayéndola (la resolución falló), reaparece — no se pierde.
  void resolveLocally(String taskId) {
    _locallyResolved.add(taskId);
    notifyListeners();
    refresh();
  }

  /// Pospone una tarea agregada (reorder/perishable) 24h.
  Future<void> dismiss(String taskId) async {
    _locallyResolved.add(taskId); // feedback inmediato
    notifyListeners();
    try {
      await _api.dismissTask(taskId);
    } catch (_) {
      _locallyResolved.remove(taskId); // si falló, vuelve a aparecer
    }
    await refresh();
  }

  Map<String, dynamic> get counts => _counts;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
