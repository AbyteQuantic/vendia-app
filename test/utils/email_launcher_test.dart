// Spec: specs/032-email-saliente/spec.md
//
// Verifica que [EmailLauncher] construye URIs `mailto:` bien formadas:
// el esquema, el destinatario y el escape de `subject`/`body` con
// caracteres especiales (ñ, acentos, #, &, ?, espacios). El escape lo
// hace el constructor `Uri()` de Dart — el test fija el contrato.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/email_launcher.dart';

void main() {
  group('EmailLauncher.buildUri', () {
    test('usa el esquema mailto', () {
      final uri = EmailLauncher.buildUri(
        to: 'cliente@example.com',
        subject: 'Hola',
        body: 'Mensaje',
      );
      expect(uri.scheme, equals('mailto'));
    });

    test('coloca el destinatario en el path', () {
      final uri = EmailLauncher.buildUri(
        to: 'cliente@example.com',
        subject: 'Hola',
        body: 'Mensaje',
      );
      expect(uri.path, equals('cliente@example.com'));
    });

    test('con destinatario vacío el path queda vacío (AC-07)', () {
      final uri = EmailLauncher.buildUri(
        to: '',
        subject: 'Hola',
        body: 'Mensaje',
      );
      expect(uri.path, isEmpty);
      // La URI sigue siendo un mailto válido sin destinatario.
      expect(uri.toString(), startsWith('mailto:?'));
    });

    test('to nulo se trata como destinatario vacío', () {
      final uri = EmailLauncher.buildUri(
        to: null,
        subject: 'Hola',
        body: 'Mensaje',
      );
      expect(uri.path, isEmpty);
    });

    test('subject y body llegan intactos al leer los queryParameters', () {
      final uri = EmailLauncher.buildUri(
        to: 'a@b.co',
        subject: 'Cotización COT-2026-0001',
        body: 'Hola Señor Muñoz',
      );
      expect(uri.queryParameters['subject'], equals('Cotización COT-2026-0001'));
      expect(uri.queryParameters['body'], equals('Hola Señor Muñoz'));
    });

    test('escapa espacios en la URI serializada', () {
      final uri = EmailLauncher.buildUri(
        to: 'a@b.co',
        subject: 'dos palabras',
        body: 'x',
      );
      // El espacio nunca aparece literal en la cadena de la URI.
      expect(uri.toString().contains(' '), isFalse);
    });

    test('escapa caracteres especiales (ñ, acentos) — round-trip correcto', () {
      const subject = 'Cotización Ñandú áéíóú';
      const body = 'Cuerpo con ñ, tildes áéíóú y símbolos.';
      final uri = EmailLauncher.buildUri(
        to: 'a@b.co',
        subject: subject,
        body: body,
      );
      // La cadena serializada no contiene los caracteres no-ASCII crudos.
      final serialized = uri.toString();
      expect(serialized.contains('ñ'), isFalse);
      expect(serialized.contains('á'), isFalse);
      // Pero al re-parsear se recuperan idénticos.
      final reparsed = Uri.parse(serialized);
      expect(reparsed.queryParameters['subject'], equals(subject));
      expect(reparsed.queryParameters['body'], equals(body));
    });

    test('escapa #, & y ? sin romper la estructura de query', () {
      const subject = 'Pedido #42 & entrega';
      const body = '¿Confirmás? Link: x';
      final uri = EmailLauncher.buildUri(
        to: 'a@b.co',
        subject: subject,
        body: body,
      );
      final reparsed = Uri.parse(uri.toString());
      expect(reparsed.queryParameters['subject'], equals(subject));
      expect(reparsed.queryParameters['body'], equals(body));
    });

    test('un body con saltos de línea sobrevive el round-trip', () {
      const body = 'Línea uno\nLínea dos\n\nLínea cuatro';
      final uri = EmailLauncher.buildUri(
        to: 'a@b.co',
        subject: 's',
        body: body,
      );
      final reparsed = Uri.parse(uri.toString());
      expect(reparsed.queryParameters['body'], equals(body));
    });
  });

  group('EmailLauncher.quoteBody', () {
    test('incluye saludo con nombre, folio, negocio y link', () {
      final body = EmailLauncher.quoteBody(
        tenantName: 'Ferretería Demo',
        customerName: 'Don Pedro',
        folio: 'COT-2026-0001',
        publicLink: 'https://tienda.vendia.store/c/abc123',
      );
      expect(body, contains('Don Pedro'));
      expect(body, contains('COT-2026-0001'));
      expect(body, contains('Ferretería Demo'));
      expect(body, contains('https://tienda.vendia.store/c/abc123'));
    });

    test('sin nombre de cliente el saludo sigue siendo válido', () {
      final body = EmailLauncher.quoteBody(
        tenantName: 'Ferretería Demo',
        customerName: '',
        folio: 'COT-2026-0001',
        publicLink: 'https://tienda.vendia.store/c/abc123',
      );
      expect(body, startsWith('Hola'));
      expect(body, contains('COT-2026-0001'));
    });
  });

  group('EmailLauncher.fiadoBody', () {
    test('incluye nombre, saldo, negocio y link cuando hay link', () {
      final body = EmailLauncher.fiadoBody(
        tenantName: 'Tienda La Esquina',
        customerName: 'Doña Ana',
        balanceText: r'$ 50.000',
        publicLink: 'https://tienda.vendia.store/f/tok9',
      );
      expect(body, contains('Doña Ana'));
      expect(body, contains(r'$ 50.000'));
      expect(body, contains('Tienda La Esquina'));
      expect(body, contains('https://tienda.vendia.store/f/tok9'));
    });

    test('sin link público el cuerpo no incluye una línea de enlace vacía', () {
      final body = EmailLauncher.fiadoBody(
        tenantName: 'Tienda La Esquina',
        customerName: 'Doña Ana',
        balanceText: r'$ 50.000',
        publicLink: '',
      );
      expect(body, contains('Doña Ana'));
      expect(body, contains(r'$ 50.000'));
      expect(body, isNot(contains('http')));
    });
  });

  group('EmailLauncher.isValidEmail', () {
    test('cadena vacía es válida (email opcional — AC-07)', () {
      expect(EmailLauncher.isValidEmail(''), isTrue);
      expect(EmailLauncher.isValidEmail('   '), isTrue);
      expect(EmailLauncher.isValidEmail(null), isTrue);
    });

    test('acepta formatos válidos', () {
      expect(EmailLauncher.isValidEmail('a@b.co'), isTrue);
      expect(EmailLauncher.isValidEmail('don.pedro@gmail.com'), isTrue);
      expect(EmailLauncher.isValidEmail('cliente+ventas@ferreteria.com.co'),
          isTrue);
      expect(EmailLauncher.isValidEmail('  test@example.com  '), isTrue);
    });

    test('rechaza formatos inválidos', () {
      expect(EmailLauncher.isValidEmail('abc'), isFalse);
      expect(EmailLauncher.isValidEmail('abc@'), isFalse);
      expect(EmailLauncher.isValidEmail('@xyz.com'), isFalse);
      expect(EmailLauncher.isValidEmail('abc@xyz'), isFalse);
      expect(EmailLauncher.isValidEmail('abc xyz@mail.com'), isFalse);
      expect(EmailLauncher.isValidEmail('abc@@mail.com'), isFalse);
    });
  });

  group('EmailLauncher.subjectForQuote', () {
    test('arma el asunto con folio y negocio', () {
      final subject = EmailLauncher.subjectForQuote(
        folio: 'COT-2026-0001',
        tenantName: 'Ferretería Demo',
      );
      expect(subject, equals('Cotización COT-2026-0001 - Ferretería Demo'));
    });
  });
}
