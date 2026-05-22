// Spec: specs/033-difusion-promociones/spec.md
//
// Tests del parser de plantillas de mensaje de promoción (F033, T-36b).
// Cubre la sustitución de `{nombre}` / `{primer_nombre}` con: nombre
// completo, solo nombre, vacío (fallback "Hola 👋") y caracteres
// especiales (ñ, acentos).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/promotion_message_template.dart';

void main() {
  group('renderPromotionMessage — nombre completo', () {
    test('sustituye {primer_nombre} por la primera palabra', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre} 👋 tenemos promo',
        customerName: 'María José Pérez',
      );
      expect(out, 'Hola María 👋 tenemos promo');
    });

    test('sustituye {nombre} por el nombre completo', () {
      final out = renderPromotionMessage(
        template: 'Gracias {nombre} por su compra',
        customerName: 'María José Pérez',
      );
      expect(out, 'Gracias María José Pérez por su compra');
    });

    test('sustituye ambos placeholders en el mismo texto', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre}, cliente {nombre}',
        customerName: 'Carlos Andrés',
      );
      expect(out, 'Hola Carlos, cliente Carlos Andrés');
    });

    test('sustituye varias ocurrencias del mismo placeholder', () {
      final out = renderPromotionMessage(
        template: '{primer_nombre}, {primer_nombre}, mire esto',
        customerName: 'Ana Lucía',
      );
      expect(out, 'Ana, Ana, mire esto');
    });
  });

  group('renderPromotionMessage — solo un nombre', () {
    test('{primer_nombre} y {nombre} coinciden cuando hay una palabra', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre} ({nombre})',
        customerName: 'Pedro',
      );
      expect(out, 'Hola Pedro (Pedro)');
    });

    test('recorta espacios sobrantes del nombre', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre}',
        customerName: '   Pedro   ',
      );
      expect(out, 'Hola Pedro');
    });
  });

  group('renderPromotionMessage — sin nombre (fallback)', () {
    test('colapsa "Hola {primer_nombre}" a "Hola 👋"', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre} 👋 tenemos promo',
        customerName: '',
      );
      expect(out, 'Hola 👋 👋 tenemos promo');
    });

    test('colapsa "Hola {nombre}" a "Hola 👋"', () {
      final out = renderPromotionMessage(
        template: 'Hola {nombre}, mire esta oferta',
        customerName: '',
      );
      expect(out, 'Hola 👋, mire esta oferta');
    });

    test('nombre solo de espacios se trata como vacío', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre}, oferta',
        customerName: '     ',
      );
      expect(out, 'Hola 👋, oferta');
    });

    test('placeholder suelto sin saludo queda vacío y sin doble espacio', () {
      final out = renderPromotionMessage(
        template: 'Cliente {nombre} aproveche',
        customerName: '',
      );
      expect(out, 'Cliente aproveche');
    });

    test('no deja espacio antes de la coma al vaciar el placeholder', () {
      final out = renderPromotionMessage(
        template: 'Saludos {nombre}, gracias',
        customerName: '',
      );
      expect(out, 'Saludos, gracias');
    });

    test('saludo case-insensitive también colapsa', () {
      final out = renderPromotionMessage(
        template: 'HOLA {primer_nombre} aproveche',
        customerName: '',
      );
      expect(out, 'HOLA 👋 aproveche');
    });
  });

  group('renderPromotionMessage — caracteres especiales', () {
    test('preserva la ñ y los acentos en el nombre', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre}',
        customerName: 'Iñaki Muñoz',
      );
      expect(out, 'Hola Iñaki');
    });

    test('preserva acentos en el nombre completo', () {
      final out = renderPromotionMessage(
        template: 'Gracias {nombre}',
        customerName: 'José Andrés Gómez',
      );
      expect(out, 'Gracias José Andrés Gómez');
    });

    test('preserva emojis y links del texto base', () {
      final out = renderPromotionMessage(
        template: 'Hola {primer_nombre} 👋 vea: https://x.co/p/abc',
        customerName: 'Sofía',
      );
      expect(out, 'Hola Sofía 👋 vea: https://x.co/p/abc');
    });
  });

  group('renderPromotionMessage — sin placeholders', () {
    test('plantilla sin placeholders se devuelve igual', () {
      final out = renderPromotionMessage(
        template: 'Tenemos 20% de descuento esta semana',
        customerName: 'Cualquiera',
      );
      expect(out, 'Tenemos 20% de descuento esta semana');
    });

    test('plantilla vacía devuelve cadena vacía', () {
      final out = renderPromotionMessage(template: '', customerName: 'Ana');
      expect(out, '');
    });
  });
}
