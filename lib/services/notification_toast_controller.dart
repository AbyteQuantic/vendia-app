// Spec: specs/056-notificaciones-cta-toast-push/spec.md
//
// Estado del toast persistente de notificaciones. Recibe el feed que ya
// pollea el POS y expone la última notificación NO leída que el usuario
// no haya cerrado. El toast vive hasta que el usuario lo cierra (no se
// auto-oculta), por eso recordamos los ids descartados.

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';

class NotificationToastController extends ChangeNotifier {
  AppNotification? _current;
  final Set<String> _dismissed = <String>{};

  AppNotification? get current => _current;
  bool get hasToast => _current != null;

  /// Recibe el feed más reciente (orden desc, como lo entrega el POS) y
  /// muestra la notificación NO leída más nueva que el usuario no haya
  /// cerrado. Idempotente: si ya está visible esa misma, no notifica.
  void offer(List<AppNotification> items) {
    for (final n in items) {
      if (n.isRead || _dismissed.contains(n.id)) continue;
      if (_current?.id == n.id) return; // ya visible, sin cambios
      _current = n;
      notifyListeners();
      return;
    }
    // Si la actual ya fue leída/quitada del feed, la bajamos.
    if (_current != null &&
        !items.any((n) => n.id == _current!.id && !n.isRead)) {
      _current = null;
      notifyListeners();
    }
  }

  /// Cierra el toast actual y lo recuerda para no reaparecerlo.
  void dismiss() {
    final id = _current?.id;
    if (id != null) _dismissed.add(id);
    if (_current != null) {
      _current = null;
      notifyListeners();
    }
  }
}
