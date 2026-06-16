// Spec: specs/056-notificaciones-cta-toast-push/spec.md

import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/app_notification.dart';
import 'package:vendia_pos/utils/notification_router.dart';

AppNotification _n({
  String type = 'info',
  String? deepLink,
  String? orderId,
  String? fiadoId,
  String? productId,
}) {
  return AppNotification(
    id: '1',
    kind: AppNotification.kindFromType(type),
    title: 't',
    body: 'b',
    isRead: false,
    createdAt: null,
    rawType: type,
    orderId: orderId,
    fiadoId: fiadoId,
    productId: productId,
    deepLink: deepLink,
  );
}

void main() {
  group('destinationFor', () {
    test('deep_link /pedidos/{id} → pedidos con foco', () {
      final d = destinationFor(_n(deepLink: '/pedidos/abc-123'));
      expect(d.target, NotificationTarget.onlineOrders);
      expect(d.focusId, 'abc-123');
      expect(d.isRoutable, isTrue);
    });

    test('deep_link /inventario/{id} → inventario con foco', () {
      final d = destinationFor(_n(deepLink: '/inventario/prod-9'));
      expect(d.target, NotificationTarget.inventory);
      expect(d.focusId, 'prod-9');
    });

    test('deep_link /fiado/{id} → fiado con foco', () {
      final d = destinationFor(_n(deepLink: '/fiado/f-7'));
      expect(d.target, NotificationTarget.fiado);
      expect(d.focusId, 'f-7');
    });

    test('sin deep_link, kind webOrder + orderId → pedidos', () {
      final d = destinationFor(_n(type: 'online_order', orderId: 'o-1'));
      expect(d.target, NotificationTarget.onlineOrders);
      expect(d.focusId, 'o-1');
    });

    test('stock_low (system) con productId → inventario accionable', () {
      final d = destinationFor(_n(type: 'stock_low', productId: 'p-5'));
      expect(d.target, NotificationTarget.inventory);
      expect(d.focusId, 'p-5');
      expect(d.isRoutable, isTrue);
    });

    test('mensaje de prueba (system sin payload) → no accionable', () {
      final d = destinationFor(_n(type: 'info'));
      expect(d.target, NotificationTarget.none);
      expect(d.isRoutable, isFalse);
    });
  });

  group('ctaLabelFor', () {
    test('etiquetas por módulo', () {
      expect(ctaLabelFor(NotificationTarget.onlineOrders), 'Ver pedido');
      expect(ctaLabelFor(NotificationTarget.fiado), 'Ver fiado');
      expect(ctaLabelFor(NotificationTarget.inventory), 'Reponer stock');
      expect(ctaLabelFor(NotificationTarget.none), '');
    });
  });
}
