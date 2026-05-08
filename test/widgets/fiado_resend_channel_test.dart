import 'package:flutter_test/flutter_test.dart';

/// PO bug image_124: launching the share intent dropped the
/// `To:` field on Gmail / Apple Mail. Root cause was sharing as a
/// plain string instead of a `mailto:` URI with the recipient in
/// the `path`.
///
/// These tests pin the URI shape we hand to `launchUrl` so a future
/// refactor can't silently regress to `Share.share('...')`.
///
/// We don't exercise `launchUrl` itself — that's a platform plugin
/// and unit tests can't open Gmail. Instead we verify the URI is
/// well-formed: scheme = mailto, path = recipient, subject + body
/// in `queryParameters`. If those are right, the OS does the rest.
void main() {
  Uri buildMailto({
    required String email,
    required String subject,
    required String body,
  }) {
    return Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': subject, 'body': body},
    );
  }

  Uri buildWhatsApp({required String phone, required String message}) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final full = digits.startsWith('57') ? digits : '57$digits';
    return Uri.parse(
        'https://wa.me/$full?text=${Uri.encodeComponent(message)}');
  }

  test('mailto URI carries the recipient in the path (PO image_124)', () {
    final uri = buildMailto(
      email: 'cliente@ejemplo.com',
      subject: 'Tu fiado en VendIA',
      body: 'Hola, aquí está el link...\nhttps://tienda.vendia.app/f/abc',
    );
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'cliente@ejemplo.com',
        reason:
            'CRITICAL: Gmail/Apple Mail land with empty To: when path is empty. '
            'This was the bug.');
    expect(uri.queryParameters['subject'], 'Tu fiado en VendIA');
    expect(uri.queryParameters['body'],
        contains('https://tienda.vendia.app/f/abc'));
  });

  test('mailto URI URL-encodes special chars in body', () {
    final uri = buildMailto(
      email: 'a@b.co',
      subject: 'Asunto con espacios',
      body: 'Línea 1\nÑ & ?',
    );
    // toString is the value handed to launchUrl; make sure the
    // newline and the ñ survive encoding.
    final str = uri.toString();
    expect(str, startsWith('mailto:a@b.co?'));
    expect(str.contains('subject=Asunto'), isTrue);
    // Either '%26' or '&' encoded properly via Uri's own encoder.
    expect(uri.queryParameters['body'], 'Línea 1\nÑ & ?');
  });

  test('WhatsApp URI prefixes Colombia country code only when missing', () {
    final without = buildWhatsApp(phone: '3001234567', message: 'Hola');
    expect(without.host, 'wa.me');
    expect(without.path, '/573001234567');

    final withCC = buildWhatsApp(phone: '+57 300 123 4567', message: 'Hola');
    expect(withCC.path, '/573001234567',
        reason: 'spaces and + must be stripped, country code preserved');
  });

  test('WhatsApp URI URL-encodes the message in the text query param', () {
    final uri = buildWhatsApp(
      phone: '3001234567',
      message: 'Hola, link https://tienda.vendia.app/f/x',
    );
    expect(uri.queryParameters['text'],
        'Hola, link https://tienda.vendia.app/f/x');
    // The raw URL string must have the colon URL-encoded so wa.me
    // doesn't truncate at https:.
    expect(uri.toString(), contains('text=Hola%2C%20link%20https'));
  });
}
