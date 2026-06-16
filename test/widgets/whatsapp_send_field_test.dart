// Spec: specs/055-cuenta-mesa-whatsapp/spec.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/whatsapp_send_field.dart';

void main() {
  testWidgets('número válido → dispara onSend con el texto crudo',
      (tester) async {
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WhatsappSendField(onSend: (p) => sent = p),
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('table_qr_whatsapp_input')), '300 123 4567');
    await tester.tap(find.byKey(const Key('table_qr_whatsapp_send')));
    await tester.pump();

    expect(sent, '300 123 4567');
  });

  testWidgets('número corto → NO dispara onSend y muestra error',
      (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WhatsappSendField(onSend: (_) => called = true),
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('table_qr_whatsapp_input')), '123');
    await tester.tap(find.byKey(const Key('table_qr_whatsapp_send')));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Escribe un número de WhatsApp válido'), findsOneWidget);
  });
}
