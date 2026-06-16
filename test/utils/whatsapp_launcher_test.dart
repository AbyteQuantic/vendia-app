// Spec: specs/055-cuenta-mesa-whatsapp/spec.md

import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vendia_pos/utils/whatsapp_launcher.dart';

void main() {
  group('normalizeCoWhatsappNumber', () {
    test('celular CO de 10 dígitos → antepone 57', () {
      expect(normalizeCoWhatsappNumber('3001234567'), '573001234567');
    });

    test('limpia espacios, guiones y paréntesis', () {
      expect(normalizeCoWhatsappNumber('(300) 123-4567'), '573001234567');
    });

    test('ya con indicativo 57 → se respeta', () {
      expect(normalizeCoWhatsappNumber('+57 300 123 4567'), '573001234567');
    });

    test('fijo de 10 dígitos que NO empieza por 3 → sin 57', () {
      expect(normalizeCoWhatsappNumber('6011234567'), '6011234567');
    });

    test('vacío → vacío', () {
      expect(normalizeCoWhatsappNumber('  '), '');
    });
  });

  group('launchWhatsapp', () {
    test('número vacío → false sin intentar abrir', () async {
      var called = false;
      final ok = await launchWhatsapp(
        phone: '',
        message: 'hola',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          called = true;
          return true;
        },
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('arma wa.me con número normalizado y texto codificado', () async {
      Uri? captured;
      final ok = await launchWhatsapp(
        phone: '3001234567',
        message: 'Cuenta de Mesa 1: hola & chao',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          captured = uri;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(captured!.host, 'wa.me');
      expect(captured!.path, '/573001234567');
      // El texto va URL-encoded (el espacio y el & no rompen la query).
      expect(captured!.query, contains('text=Cuenta%20de%20Mesa%201'));
      expect(captured!.queryParameters['text'], 'Cuenta de Mesa 1: hola & chao');
    });

    test('launcher devuelve false → propaga false', () async {
      final ok = await launchWhatsapp(
        phone: '3001234567',
        message: 'x',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async => false,
      );
      expect(ok, isFalse);
    });
  });
}
