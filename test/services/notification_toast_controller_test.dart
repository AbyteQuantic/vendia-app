// Spec: specs/056-notificaciones-cta-toast-push/spec.md

import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/app_notification.dart';
import 'package:vendia_pos/services/notification_toast_controller.dart';

AppNotification _n(String id, {bool read = false, String type = 'online_order'}) {
  return AppNotification(
    id: id,
    kind: AppNotification.kindFromType(type),
    title: 'n$id',
    body: 'b',
    isRead: read,
    createdAt: null,
    rawType: type,
  );
}

void main() {
  test('muestra la primera NO leída del feed (la más nueva)', () {
    final c = NotificationToastController();
    c.offer([_n('a'), _n('b', read: true)]);
    expect(c.current?.id, 'a');
    expect(c.hasToast, isTrue);
  });

  test('feed solo con leídas → sin toast', () {
    final c = NotificationToastController();
    c.offer([_n('a', read: true)]);
    expect(c.hasToast, isFalse);
  });

  test('dismiss la oculta y NO reaparece en el siguiente feed', () {
    final c = NotificationToastController();
    c.offer([_n('a')]);
    expect(c.current?.id, 'a');
    c.dismiss();
    expect(c.hasToast, isFalse);
    c.offer([_n('a')]); // mismo feed
    expect(c.hasToast, isFalse);
  });

  test('una notificación más nueva reemplaza a la visible', () {
    final c = NotificationToastController();
    c.offer([_n('b')]);
    expect(c.current?.id, 'b');
    // Llega 'a' más nueva (primera del feed desc).
    c.offer([_n('a'), _n('b')]);
    expect(c.current?.id, 'a');
  });

  test('re-ofrecer el mismo feed no cambia la actual (idempotente)', () {
    final c = NotificationToastController();
    c.offer([_n('a')]);
    var notified = 0;
    c.addListener(() => notified++);
    c.offer([_n('a')]);
    expect(notified, 0);
    expect(c.current?.id, 'a');
  });

  test('si la actual sale del feed (leída/quitada) se baja', () {
    final c = NotificationToastController();
    c.offer([_n('a')]);
    expect(c.hasToast, isTrue);
    c.offer([_n('a', read: true)]);
    expect(c.hasToast, isFalse);
  });

  test('stock_low no genera toast legacy (ya cubierto por Task reorder_out, Spec 078 F3)', () {
    final c = NotificationToastController();
    c.offer([_n('a', type: 'stock_low')]);
    expect(c.hasToast, isFalse);
  });

  test('stock_low no bloquea que otra notificación sí muestre toast', () {
    final c = NotificationToastController();
    c.offer([_n('a', type: 'stock_low'), _n('b', type: 'fiado_accepted')]);
    expect(c.current?.id, 'b');
  });
}
