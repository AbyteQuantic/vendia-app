import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/support/support_screen.dart';

/// Widget tests for the Phase 3 Support Hub entry point.
///
/// The screen accepts two injected callbacks (submitTicket, openWhatsapp)
/// so we can exercise the full happy-path + error-path without booting
/// the Dio stack or calling the real url_launcher (neither are mocked
/// in widget tests).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders subject, message and both CTAs', (tester) async {
    await tester.pumpWidget(wrap(SupportScreen(
      submitTicket: ({required subject, required message}) async {},
      openWhatsapp: (_) async {},
      whatsappNumber: '573001112233',
    )));

    expect(find.byKey(const Key('support_subject')), findsOneWidget);
    expect(find.byKey(const Key('support_message')), findsOneWidget);
    expect(find.byKey(const Key('support_submit')), findsOneWidget);
    expect(find.byKey(const Key('support_whatsapp')), findsOneWidget);
  });

  testWidgets('empty subject + empty message shows validation errors',
      (tester) async {
    await tester.pumpWidget(wrap(SupportScreen(
      submitTicket: ({required subject, required message}) async {},
      openWhatsapp: (_) async {},
      whatsappNumber: '573001112233',
    )));

    await tester.tap(find.byKey(const Key('support_submit')));
    await tester.pump();

    expect(find.text('Ingresa un asunto'), findsOneWidget);
    expect(find.text('Cuéntanos más'), findsOneWidget);
  });

  testWidgets('successful submit calls the API + shows success banner',
      (tester) async {
    String? capturedSubject;
    String? capturedMessage;

    await tester.pumpWidget(wrap(SupportScreen(
      submitTicket: ({required subject, required message}) async {
        capturedSubject = subject;
        capturedMessage = message;
      },
      openWhatsapp: (_) async {},
      whatsappNumber: '573001112233',
    )));

    await tester.enterText(
        find.byKey(const Key('support_subject')), 'No sincroniza');
    await tester.enterText(
        find.byKey(const Key('support_message')),
        'El catálogo queda girando');
    await tester.tap(find.byKey(const Key('support_submit')));
    await tester.pumpAndSettle();

    expect(capturedSubject, 'No sincroniza');
    expect(capturedMessage, 'El catálogo queda girando');
    expect(find.byKey(const Key('support_success')), findsOneWidget);
    expect(find.text('Ticket enviado. Te contactamos pronto.'), findsOneWidget);
  });

  testWidgets('failed submit shows the error banner + keeps the form filled',
      (tester) async {
    await tester.pumpWidget(wrap(SupportScreen(
      submitTicket: ({required subject, required message}) async {
        throw Exception('boom');
      },
      openWhatsapp: (_) async {},
      whatsappNumber: '573001112233',
    )));

    await tester.enterText(
        find.byKey(const Key('support_subject')), 'asunto x');
    await tester.enterText(
        find.byKey(const Key('support_message')), 'mensaje x');
    await tester.tap(find.byKey(const Key('support_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support_error')), findsOneWidget);
    expect(find.text('No se pudo enviar. Intente de nuevo o use WhatsApp.'),
        findsOneWidget);
    // Form keeps values so the user doesn't have to re-type.
    expect(find.text('asunto x'), findsOneWidget);
    expect(find.text('mensaje x'), findsOneWidget);
  });

  testWidgets('WhatsApp CTA invokes the openWhatsapp callback with the configured number',
      (tester) async {
    String? capturedNumber;
    await tester.pumpWidget(wrap(SupportScreen(
      submitTicket: ({required subject, required message}) async {},
      openWhatsapp: (n) async {
        capturedNumber = n;
      },
      whatsappNumber: '573009998888',
    )));

    await tester.tap(find.byKey(const Key('support_whatsapp')));
    await tester.pump();

    expect(capturedNumber, '573009998888');
  });
}
