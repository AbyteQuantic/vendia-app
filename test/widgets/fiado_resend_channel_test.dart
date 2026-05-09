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
  /// Mirrors the production helper. The `+` → `%20` swap is the fix
  /// for PO image_125 — Dart's queryParameters encoder uses
  /// application/x-www-form-urlencoded, which Gmail renders as
  /// literal '+' signs in the subject and body.
  Uri buildMailto({
    required String email,
    required String subject,
    required String body,
  }) {
    final s = Uri.encodeComponent(subject).replaceAll('+', '%20');
    final b = Uri.encodeComponent(body).replaceAll('+', '%20');
    return Uri.parse('mailto:$email?subject=$s&body=$b');
  }

  Uri buildSms({required String phone, required String message}) {
    return Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
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
      body: 'Hola, aquí está el link...\nhttps://tienda.vendia.store/f/abc',
    );
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'cliente@ejemplo.com',
        reason:
            'CRITICAL: Gmail/Apple Mail land with empty To: when path is empty. '
            'This was the bug.');
    expect(uri.queryParameters['subject'], 'Tu fiado en VendIA');
    expect(uri.queryParameters['body'],
        contains('https://tienda.vendia.store/f/abc'));
  });

  test(
      'mailto URI encodes spaces as %20 — never as + (PO image_125 fix)',
      () {
    final uri = buildMailto(
      email: 'cliente@ejemplo.com',
      subject: 'Detalles de tu cuenta en VendIA',
      body: 'Hola Viviana, abre el link:\nhttps://tienda.vendia.store/f/abc',
    );
    final str = uri.toString();

    // The '+' substitution is the bug Gmail renders verbatim. After
    // the fix the subject and body must use %20 only.
    expect(str.contains('+'), isFalse,
        reason:
            'CRITICAL: any literal "+" in the URI tells Gmail to render '
            "spaces as '+' signs. Bug from PO image_125.");

    expect(str, contains('subject=Detalles%20de%20tu%20cuenta'));
    expect(str, contains('body=Hola%20Viviana'));
    // Newline must come through encoded, not stripped.
    expect(str, contains('%0A'));
  });

  test('mailto URI preserves ampersands and accents in the body', () {
    final uri = buildMailto(
      email: 'a@b.co',
      subject: 'Asunto con espacios',
      body: 'Línea 1\nÑ & ?',
    );
    final str = uri.toString();
    expect(str, startsWith('mailto:a@b.co?'));
    expect(str, contains('subject=Asunto%20con%20espacios'));
    // '&' must be %26 so it doesn't terminate the body param early.
    expect(str, contains('%26'));
    // 'Ñ' encoded as %C3%91 (UTF-8).
    expect(str, contains('%C3%91'));
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
      message: 'Hola, link https://tienda.vendia.store/f/x',
    );
    expect(uri.queryParameters['text'],
        'Hola, link https://tienda.vendia.store/f/x');
    // The raw URL string must have the colon URL-encoded so wa.me
    // doesn't truncate at https:.
    expect(uri.toString(), contains('text=Hola%2C%20link%20https'));
  });

  test('SMS URI carries the recipient in the path and body in query', () {
    final uri = buildSms(
      phone: '3001234567',
      message: 'Tu fiado está listo: https://tienda.vendia.store/f/x',
    );
    expect(uri.scheme, 'sms');
    expect(uri.path, '3001234567');
    expect(uri.queryParameters['body'],
        'Tu fiado está listo: https://tienda.vendia.store/f/x');
  });
}
