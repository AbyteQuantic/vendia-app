// Spec: specs/056-notificaciones-cta-toast-push/spec.md
//
// Router puro de notificaciones: decide a qué módulo lleva cada
// notificación y con qué id de foco (dato precargado). Es pura a
// propósito (no toca Navigator ni importa pantallas) para poder
// testear la tabla de mapeo sin MaterialApp; el sheet y el handler de
// push consumen [destinationFor] y construyen la ruta concreta.

import '../models/app_notification.dart';

/// Módulos a los que una notificación puede llevar.
enum NotificationTarget { onlineOrders, fiado, inventory, none }

/// Destino resuelto: módulo + id de foco opcional (pedido/fiado/producto)
/// para precargar ESE dato en la pantalla destino.
class NotificationDestination {
  final NotificationTarget target;
  final String? focusId;

  const NotificationDestination(this.target, [this.focusId]);

  bool get isRoutable => target != NotificationTarget.none;
}

/// Resuelve un destino a partir de SOLO un path de deep-link
/// (`/pedidos/{id}`, `/inventario/{id}`, `/fiado/{id}`). Lo usa el
/// handler de push, que únicamente recibe el string del payload.
NotificationDestination destinationForPath(String deepLink) {
  final seg = Uri.tryParse(deepLink)?.pathSegments ?? const <String>[];
  if (seg.isEmpty) return const NotificationDestination(NotificationTarget.none);
  final id = seg.length >= 2 ? seg.last : null;
  switch (seg.first) {
    case 'pedidos':
    case 'pedido':
      return NotificationDestination(NotificationTarget.onlineOrders, id);
    case 'inventario':
    case 'producto':
      return NotificationDestination(NotificationTarget.inventory, id);
    case 'fiado':
    case 'fiados':
      return NotificationDestination(NotificationTarget.fiado, id);
  }
  return const NotificationDestination(NotificationTarget.none);
}

/// Resuelve el destino de [n]. El `deep_link` del backend manda; si no
/// viene, cae al `kind` + ids derivados. Devuelve `none` cuando no hay
/// a dónde llevar (mensajes de sistema sin payload, ej. prueba).
NotificationDestination destinationFor(AppNotification n) {
  final dl = n.deepLink;
  if (dl != null) {
    final byPath = destinationForPath(dl);
    if (byPath.isRoutable) {
      // Completa el id de foco con el del payload si el path no lo trae.
      final id = byPath.focusId ??
          switch (byPath.target) {
            NotificationTarget.onlineOrders => n.orderId,
            NotificationTarget.inventory => n.productId,
            NotificationTarget.fiado => n.fiadoId,
            NotificationTarget.none => null,
          };
      return NotificationDestination(byPath.target, id);
    }
  }

  switch (n.kind) {
    case NotificationKind.webOrder:
      return NotificationDestination(
          NotificationTarget.onlineOrders, n.orderId);
    case NotificationKind.fiado:
      return NotificationDestination(NotificationTarget.fiado, n.fiadoId);
    case NotificationKind.system:
      // Stock bajo es `system` por color/ícono pero SÍ es accionable
      // cuando trae producto o el tipo empieza por "stock".
      if (n.productId != null ||
          n.rawType.toLowerCase().startsWith('stock')) {
        return NotificationDestination(
            NotificationTarget.inventory, n.productId);
      }
      return const NotificationDestination(NotificationTarget.none);
  }
}

/// Texto del botón de acción (CTA) por módulo destino.
String ctaLabelFor(NotificationTarget t) {
  switch (t) {
    case NotificationTarget.onlineOrders:
      return 'Ver pedido';
    case NotificationTarget.fiado:
      return 'Ver fiado';
    case NotificationTarget.inventory:
      return 'Reponer stock';
    case NotificationTarget.none:
      return '';
  }
}
