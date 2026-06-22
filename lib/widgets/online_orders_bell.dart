import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../screens/online_orders/online_orders_screen.dart';
import '../screens/mandados/mandados_screen.dart';
import '../screens/recipes/recipes_home_screen.dart';
import '../services/task_center_controller.dart';
import '../theme/app_theme.dart';
import 'task_center_sheet.dart';

/// Campana ÚNICA del Centro de Tareas (Spec 078). Reemplaza el polling propio:
/// el badge lee el [TaskCenterController] (un solo poller app-wide) y al tocar
/// abre el Centro de Tareas unificado. Lectura defensiva del Provider para que
/// los tests que montan la campana sin Provider la rendericen en cero.
class OnlineOrdersBell extends StatefulWidget {
  const OnlineOrdersBell({
    super.key,
    this.enabled = true,
    this.pollInterval = const Duration(seconds: 15),
    this.size = 44,
    this.iconColor,
  });

  final bool enabled;
  final Duration pollInterval;
  final double size;
  final Color? iconColor;

  @override
  State<OnlineOrdersBell> createState() => _OnlineOrdersBellState();
}

class _OnlineOrdersBellState extends State<OnlineOrdersBell> {
  TaskCenterController? _ctrl() {
    try {
      return context.read<TaskCenterController>();
    } catch (_) {
      return null; // sin Provider (tests) → campana estática en cero
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.enabled) _ctrl()?.start(); // idempotente (un solo Timer)
  }

  void _open() {
    HapticFeedback.lightImpact();
    final ctrl = _ctrl();
    if (ctrl == null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnlineOrdersScreen()));
      return;
    }
    showTaskCenter(context, onOpenTask: _navigateToTask);
  }

  // Navega a la pantalla dueña de la tarea; al volver, refresca el Centro.
  void _navigateToTask(Task t) {
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
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen!))
        .then((_) => _ctrl()?.refresh());
  }

  @override
  Widget build(BuildContext context) {
    int count = 0;
    bool urgent = false;
    try {
      final ctrl = context.watch<TaskCenterController>();
      count = ctrl.openCount;
      urgent = ctrl.hasUrgent;
    } catch (_) {
      // sin Provider → cero
    }
    final active = count > 0;
    final badgeColor = urgent ? AppTheme.error : AppTheme.warning;

    return Semantics(
      button: true,
      label: active ? 'Tareas pendientes: $count' : 'Tareas, ninguna pendiente',
      child: GestureDetector(
        key: const Key('dashboard_orders_bell'),
        onTap: _open,
        child: SizedBox(
          width: widget.size + 8,
          height: widget.size + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: active ? badgeColor.withValues(alpha: 0.08) : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    active ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                    color: active ? badgeColor : (widget.iconColor ?? AppTheme.textSecondary),
                    size: 24,
                  ),
                ),
              ),
              if (active)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    key: const Key('dashboard_orders_badge'),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
