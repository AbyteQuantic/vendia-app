// Spec: specs/056-notificaciones-cta-toast-push/spec.md

import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/utils/notification_navigation.dart';
import 'package:vendia_pos/utils/notification_router.dart';

void main() {
  group('notificationRouteBuilder', () {
    test('targets accionables devuelven builder', () {
      expect(
          notificationRouteBuilder(
              const NotificationDestination(NotificationTarget.onlineOrders, 'o')),
          isNotNull);
      expect(
          notificationRouteBuilder(
              const NotificationDestination(NotificationTarget.fiado, 'f')),
          isNotNull);
      expect(
          notificationRouteBuilder(
              const NotificationDestination(NotificationTarget.inventory, 'p')),
          isNotNull);
    });

    test('none → null (no navega)', () {
      expect(
          notificationRouteBuilder(
              const NotificationDestination(NotificationTarget.none)),
          isNull);
    });
  });
}
