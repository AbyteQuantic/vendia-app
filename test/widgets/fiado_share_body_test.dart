import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/pos/cuaderno_fiados_screen.dart';

/// PO Dynamic Branding mandate — the share body MUST embed the
/// merchant's identity (tenant + cashier) so the customer never
/// reads a generic "VendIA"-only message.
///
/// These tests pin the template so a future refactor can't drift
/// back to the static copy.
void main() {
  test('embeds tenantName, senderName and customer greeting', () {
    final body = buildFiadoShareBody(
      customerName: 'Viviana',
      tenantName: 'Tienda La Esquina',
      senderName: 'Bryan',
      fiadoUrl: 'https://tienda.vendia.app/f/abc',
    );
    expect(body, startsWith('Hola Viviana,\n\n'));
    expect(body, contains('Somos de Tienda La Esquina.'));
    expect(body, contains('https://tienda.vendia.app/f/abc'));
    // Signature must pair sender + tenant on consecutive lines
    // ("Atentamente,\n<sender>\n<tenant>") — the customer reads
    // both who wrote and which business it came from.
    expect(body, endsWith('Atentamente,\nBryan\nTienda La Esquina'));
  });

  test('falls back to plain "Hola" when the customer has no name', () {
    final body = buildFiadoShareBody(
      customerName: '',
      tenantName: 'Mini Mercado',
      senderName: 'Ana',
      fiadoUrl: 'https://tienda.vendia.app/f/x',
    );
    expect(body, startsWith('Hola,\n\n'),
        reason:
            'no customer name → plain greeting, never "Hola , " or "Hola null"');
    expect(body, contains('Somos de Mini Mercado.'));
  });

  test('preserves explicit blank-line separators (multi-paragraph copy)',
      () {
    final body = buildFiadoShareBody(
      customerName: 'Pedro',
      tenantName: 'Tienda X',
      senderName: 'Sofía',
      fiadoUrl: 'https://tienda.vendia.app/f/y',
    );
    // Three blank-line breaks: greeting → body, body → URL, URL →
    // outro / signature. We don't pin the count exactly because
    // future copy edits may add/remove paragraphs, but we DO pin
    // that there are at least 3 blank lines so SMS/email readers
    // surface the URL as a tappable line of its own.
    final blankLineCount =
        '\n\n'.allMatches(body).length;
    expect(blankLineCount, greaterThanOrEqualTo(3));
  });

  test('greeting ignores leading/trailing whitespace in the name', () {
    final body = buildFiadoShareBody(
      customerName: '   Carolina   ',
      tenantName: 'X',
      senderName: 'Y',
      fiadoUrl: 'https://tienda.vendia.app/f/z',
    );
    expect(body, startsWith('Hola Carolina,'),
        reason: 'whitespace must be trimmed before interpolation');
  });
}
