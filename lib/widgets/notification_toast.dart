// Spec: specs/056-notificaciones-cta-toast-push/spec.md
//
// Toast persistente de la última notificación. Se monta global (vía
// MaterialApp.builder) sobre cualquier pantalla y NO se auto-oculta:
// vive hasta que el usuario toca su CTA o lo cierra con la X. Reusa el
// router/navegación de notificaciones para llevar al módulo correcto
// con el dato precargado.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_notification.dart';
import '../models/task.dart';
import '../services/notification_toast_controller.dart';
import '../services/task_center_controller.dart';
import '../theme/app_theme.dart';
import '../utils/notification_navigation.dart';
import '../utils/notification_router.dart';
import 'premium_upsell_sheet.dart';
import 'task_center_sheet.dart';

class NotificationToast extends StatelessWidget {
  const NotificationToast({super.key});

  @override
  Widget build(BuildContext context) {
    // PRIORIDAD: una TAREA urgente (pedido por aceptar, mesa por cobrar) interrumpe
    // primero — y una sola vez (Spec 078 F3). Lectura defensiva del Provider.
    TaskCenterController? tc;
    try {
      tc = context.watch<TaskCenterController>();
    } catch (_) {}
    final task = tc?.toastCandidate;
    if (task != null) return _taskToast(context, task);

    final ctrl = context.watch<NotificationToastController>();
    final n = ctrl.current;
    if (n == null) return const SizedBox.shrink();

    final visual = NotificationVisual.of(n.kind);
    final dest = destinationFor(n);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        key: const Key('notification_toast'),
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: visual.color.withValues(alpha: 0.30)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                    if (dest.isRoutable) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        key: const Key('notification_toast_cta'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _open(context, dest),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  ctaLabelFor(dest.target),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: visual.color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: visual.color),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Cierre — el toast persiste hasta que el usuario lo toca.
              // Objetivo táctil ≥48dp (gerontodiseño).
              IconButton(
                key: const Key('notification_toast_close'),
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close_rounded),
                color: AppTheme.textSecondary,
                onPressed: () =>
                    context.read<NotificationToastController>().dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Toast de una TAREA urgente: mismo estilo del de notificaciones, CTA abre el
  // Centro de Tareas; persiste hasta que el usuario actúa o lo cierra. Spec 078.
  Widget _taskToast(BuildContext context, Task task) {
    final color = task.urgency == 'critical' ? AppTheme.error : AppTheme.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        key: const Key('task_toast'),
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.notifications_active_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.black87)),
                if (task.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(task.subtitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, height: 1.3, color: AppTheme.textSecondary)),
                ],
                const SizedBox(height: 8),
                InkWell(
                  key: const Key('task_toast_cta'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openTaskCenter(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(task.actionLabel.isEmpty ? 'Ver' : task.actionLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                    ]),
                  ),
                ),
              ]),
            ),
            IconButton(
              key: const Key('task_toast_close'),
              iconSize: 22,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close_rounded),
              color: AppTheme.textSecondary,
              onPressed: () => context.read<TaskCenterController>().dismissToast(),
            ),
          ]),
        ),
      ),
    );
  }

  void _openTaskCenter(BuildContext context) {
    context.read<TaskCenterController>().dismissToast();
    final navCtx = PremiumUpsellController.navigatorKey.currentContext;
    if (navCtx != null) openTaskCenter(navCtx);
  }

  void _open(BuildContext context, NotificationDestination dest) {
    context.read<NotificationToastController>().dismiss();
    final builder = notificationRouteBuilder(dest);
    if (builder == null) return;
    // El toast vive sobre el Navigator (MaterialApp.builder), así que
    // navegamos por la key global, no por el context local.
    PremiumUpsellController.navigatorKey.currentState
        ?.push(MaterialPageRoute(builder: builder));
  }
}
