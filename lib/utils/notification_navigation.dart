// Spec: specs/056-notificaciones-cta-toast-push/spec.md
//
// Puente entre el router puro ([NotificationDestination]) y las
// pantallas concretas. Aislado acá para que el sheet, el toast y el
// handler de push deep-link usen EXACTAMENTE el mismo destino + foco.

import 'package:flutter/material.dart';

import '../screens/inventory/manage_inventory_screen.dart';
import '../screens/online_orders/online_orders_screen.dart';
import '../screens/pos/cuaderno_fiados_screen.dart';
import 'notification_router.dart';

/// Builder de la pantalla destino precargando el id de foco, o `null`
/// si el destino no es navegable.
WidgetBuilder? notificationRouteBuilder(NotificationDestination dest) {
  switch (dest.target) {
    case NotificationTarget.onlineOrders:
      return (_) => OnlineOrdersScreen(focusOrderId: dest.focusId);
    case NotificationTarget.fiado:
      return (_) => CuadernoFiadosScreen(focusFiadoId: dest.focusId);
    case NotificationTarget.inventory:
      return (_) => ManageInventoryScreen(focusProductId: dest.focusId);
    case NotificationTarget.none:
      return null;
  }
}
