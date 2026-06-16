// Spec: specs/056-notificaciones-cta-toast-push/spec.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/models/app_notification.dart';
import 'package:vendia_pos/services/notification_toast_controller.dart';
import 'package:vendia_pos/widgets/notification_toast.dart';

AppNotification _n(String type, {String? orderId, String? productId}) {
  return AppNotification(
    id: 'x',
    kind: AppNotification.kindFromType(type),
    title: 'Nuevo pedido en línea',
    body: 'Yeimy pidió por \$36.250',
    isRead: false,
    createdAt: DateTime.now(),
    rawType: type,
    orderId: orderId,
    productId: productId,
  );
}

Future<void> _pump(WidgetTester tester, NotificationToastController c) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<NotificationToastController>.value(
      value: c,
      child: const MaterialApp(
        home: Scaffold(body: NotificationToast()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('sin notificación → no renderea el toast', (tester) async {
    final c = NotificationToastController();
    await _pump(tester, c);
    expect(find.byKey(const Key('notification_toast')), findsNothing);
  });

  testWidgets('con notificación accionable → toast con título y CTA',
      (tester) async {
    final c = NotificationToastController()..offer([_n('online_order', orderId: 'o-1')]);
    await _pump(tester, c);
    expect(find.byKey(const Key('notification_toast')), findsOneWidget);
    expect(find.text('Nuevo pedido en línea'), findsOneWidget);
    expect(find.byKey(const Key('notification_toast_cta')), findsOneWidget);
    expect(find.text('Ver pedido'), findsOneWidget);
  });

  testWidgets('cerrar (X) oculta el toast — persiste hasta que el usuario cierra',
      (tester) async {
    final c = NotificationToastController()..offer([_n('online_order', orderId: 'o-1')]);
    await _pump(tester, c);
    expect(find.byKey(const Key('notification_toast')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notification_toast_close')));
    await tester.pump();
    expect(find.byKey(const Key('notification_toast')), findsNothing);
  });

  testWidgets('notificación sin destino (prueba) → sin CTA', (tester) async {
    final c = NotificationToastController()..offer([_n('info')]);
    await _pump(tester, c);
    expect(find.byKey(const Key('notification_toast')), findsOneWidget);
    expect(find.byKey(const Key('notification_toast_cta')), findsNothing);
  });
}
