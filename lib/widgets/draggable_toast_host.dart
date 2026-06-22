// Spec: specs/056-notificaciones-cta-toast-push/spec.md
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../services/notification_toast_controller.dart';
import '../services/task_center_controller.dart';
import '../theme/app_theme.dart';
import 'notification_toast.dart';

/// DraggableToastHost — monta el toast como overlay que el usuario puede MOVER
/// (arrastrar) y que por DEFAULT no estorba: a los pocos segundos se AUTO-COLAPSA
/// a una pastilla pequeña en el borde; al tocarla se expande de nuevo. Recuerda la
/// posición vertical que el usuario eligió (entre aperturas y reinicios). Spec 056/078.
/// Devuelve un Positioned para vivir directo en el Stack del MaterialApp.builder.
class DraggableToastHost extends StatefulWidget {
  const DraggableToastHost({super.key});

  @override
  State<DraggableToastHost> createState() => _DraggableToastHostState();
}

class _DraggableToastHostState extends State<DraggableToastHost> {
  static const _collapseAfter = Duration(seconds: 6);
  static const _prefKey = 'toast_top_offset';

  double? _top; // desplazamiento vertical (null = default arriba)
  bool _expanded = true;
  Timer? _collapseTimer;
  String? _shownKey; // identidad del toast visible (para reiniciar el timer al cambiar)

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getDouble(_prefKey);
      if (v != null && mounted) setState(() => _top = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  // Identidad + color del toast actual leyendo ambos controladores.
  ({String key, Color color, String label})? _current() {
    try {
      final Task? t = context.watch<TaskCenterController>().toastCandidate;
      if (t != null) {
        return (
          key: 'task:${t.id}',
          color: t.urgency == 'critical' ? AppTheme.error : AppTheme.warning,
          label: t.title,
        );
      }
    } catch (_) {}
    try {
      final n = context.watch<NotificationToastController>().current;
      if (n != null) {
        return (key: 'notif:${n.id}', color: AppTheme.primary, label: n.title);
      }
    } catch (_) {}
    return null;
  }

  void _armCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseAfter, () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _expand() {
    setState(() => _expanded = true);
    _armCollapse();
  }

  @override
  Widget build(BuildContext context) {
    final cur = _current();
    final media = MediaQuery.of(context);
    final topSafe = media.padding.top + 6;
    final maxTop = media.size.height - 180;
    final clampMax = maxTop > topSafe ? maxTop : topSafe;
    final top = (_top ?? topSafe).clamp(topSafe, clampMax);

    // Cambió el toast visible → reinicia (expandido + nuevo timer de colapso).
    if (cur?.key != _shownKey) {
      _shownKey = cur?.key;
      _expanded = true;
      if (cur != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _armCollapse());
      } else {
        _collapseTimer?.cancel();
      }
    }

    if (cur == null) return const SizedBox.shrink();

    void onDragUpdate(DragUpdateDetails d) {
      setState(() => _top = ((_top ?? topSafe) + d.delta.dy).clamp(topSafe, clampMax));
    }
    void onDragEnd(_) {
      final v = _top;
      if (v != null) {
        SharedPreferences.getInstance().then((p) => p.setDouble(_prefKey, v)).catchError((_) => false);
      }
    }

    if (!_expanded) {
      // Pastilla colapsada: pequeña, en el borde derecho; tocar para expandir.
      return Positioned(
        right: 12,
        top: top,
        child: GestureDetector(
          onVerticalDragUpdate: onDragUpdate,
          onVerticalDragEnd: onDragEnd,
          child: _CollapsedPill(color: cur.color, onTap: _expand),
        ),
      );
    }

    return Positioned(
      left: 12,
      right: 12,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: const NotificationToast(grip: true),
      ),
    );
  }
}

/// Pastilla colapsada: una campanita de color sobre fondo blanco; al tocar expande.
class _CollapsedPill extends StatelessWidget {
  const _CollapsedPill({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ver aviso',
      child: GestureDetector(
        onTap: onTap,
        child: Material(
          key: const Key('toast_pill'),
          elevation: 6,
          shape: const CircleBorder(),
          shadowColor: Colors.black.withValues(alpha: 0.25),
          color: Colors.white,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.notifications_active_rounded, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
