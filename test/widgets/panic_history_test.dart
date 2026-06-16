// Spec: specs/057-panic-button-delivery/spec.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/panic_alert.dart';
import 'package:vendia_pos/widgets/panic_history.dart';

void main() {
  group('PanicAlert.fromApi', () {
    test('parsea alerta con entregas y estados', () {
      final a = PanicAlert.fromApi({
        'id': 'al-1',
        'message': 'EMERGENCIA',
        'triggered_at': '2026-06-16T15:00:00Z',
        'contact_count': 2,
        'deliveries': [
          {
            'contact_name': 'Brayan',
            'phone_number': '3223121409',
            'method': 'sms',
            'status': 'sent',
          },
          {
            'contact_name': 'Viviana',
            'phone_number': '3022798580',
            'method': 'whatsapp',
            'status': 'skipped',
            'error_detail': 'WhatsApp (Meta) no configurado',
          },
        ],
      });
      expect(a.id, 'al-1');
      expect(a.contactCount, 2);
      expect(a.deliveries.length, 2);
      expect(a.deliveries[0].statusLabel, 'Enviado');
      expect(a.deliveries[1].statusLabel, 'Canal sin configurar');
    });

    test('status labels cubren todos los casos', () {
      PanicDelivery d(String s) => PanicDelivery(
          contactName: 'x', phoneNumber: 'y', method: 'sms', status: s);
      expect(d('sent').statusLabel, 'Enviado');
      expect(d('failed').statusLabel, 'No se pudo enviar');
      expect(d('skipped').statusLabel, 'Canal sin configurar');
      expect(d('pending').statusLabel, 'Pendiente');
    });
  });

  group('PanicHistory widget', () {
    testWidgets('vacío → muestra el mensaje guía', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PanicHistory(alerts: [])),
      ));
      expect(find.textContaining('Aún no ha activado'), findsOneWidget);
    });

    testWidgets('con alerta → muestra contacto y estado', (tester) async {
      final alerts = [
        PanicAlert(
          id: 'al-1',
          message: 'EMERGENCIA',
          triggeredAt: DateTime(2026, 6, 16, 10, 5),
          contactCount: 1,
          deliveries: const [
            PanicDelivery(
              contactName: 'Brayan',
              phoneNumber: '3223121409',
              method: 'sms',
              status: 'sent',
            ),
          ],
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PanicHistory(alerts: alerts)),
      ));
      expect(find.byKey(const Key('panic_alert_al-1')), findsOneWidget);
      expect(find.text('Brayan'), findsOneWidget);
      expect(find.text('Enviado'), findsOneWidget);
    });
  });
}
