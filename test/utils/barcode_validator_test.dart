import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/barcode_validator.dart';

/// Tests del checksum GTIN (EAN-8, UPC-A, EAN-13, ITF-14).
///
/// Regresión: el validador rechazaba EAN-13 válidos reales (ej. la caja
/// de Marlboro `7702005004467`) porque pesaba los dígitos al revés. El
/// dígito de control (más a la derecha) debe pesar 1, no 3.
void main() {
  group('BarcodeValidator.validate', () {
    test('acepta EAN-13 válidos reales', () {
      // El que reportó el tendero — copiado de la caja, es válido.
      expect(BarcodeValidator.validate('7702005004467'), isNull);
      // Otros EAN-13 válidos conocidos.
      expect(BarcodeValidator.validate('4006381333931'), isNull);
      expect(BarcodeValidator.validate('0036000291452'), isNull);
    });

    test('rechaza un EAN-13 con dígito de control equivocado', () {
      // 7702005004467 es válido; cambiar el último dígito lo invalida.
      expect(
        BarcodeValidator.validate('7702005004460'),
        'Dígito de control EAN-13 inválido',
      );
    });

    test('acepta EAN-8 y UPC-A válidos', () {
      expect(BarcodeValidator.validate('96385074'), isNull); // EAN-8
      expect(BarcodeValidator.validate('036000291452'), isNull); // UPC-A (12)
    });

    test('campo vacío es válido (SKU opcional)', () {
      expect(BarcodeValidator.validate(''), isNull);
      expect(BarcodeValidator.validate('   '), isNull);
    });

    test('rechaza caracteres no numéricos', () {
      expect(BarcodeValidator.validate('77020A5004467'),
          'Solo dígitos numéricos');
    });

    test('longitud no estándar se acepta como SKU interno', () {
      expect(BarcodeValidator.validate('12345'), isNull);
      expect(BarcodeValidator.validate('123'),
          'Código muy corto (mínimo 4 dígitos)');
    });
  });

  group('BarcodeValidator.computeCheckDigit', () {
    test('calcula el dígito de control EAN-13 correcto', () {
      // Los primeros 12 dígitos del Marlboro → control 7.
      expect(BarcodeValidator.computeCheckDigit('770200500446'), '7');
      expect(BarcodeValidator.computeCheckDigit('400638133393'), '1');
    });

    test('el código + su dígito calculado es válido', () {
      const partial = '770200500446';
      final full = '$partial${BarcodeValidator.computeCheckDigit(partial)}';
      expect(BarcodeValidator.isValid(full), isTrue);
    });
  });
}
