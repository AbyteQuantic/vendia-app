// Spec: specs/083-mesas-catalogo-qr/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/pos/table_qr_scan_screen.dart';

void main() {
  group('parseMesaIdFromQr', () {
    test('extrae el id de mesa del query param', () {
      expect(
        parseMesaIdFromQr('https://tienda.vendia.store/don-brayan?mesa=abc123'),
        'abc123',
      );
    });

    test('extrae mesa aunque haya otros params', () {
      expect(
        parseMesaIdFromQr('https://tienda.vendia.store/x?sede=s1&mesa=t-9&reg=z'),
        't-9',
      );
    });

    test('devuelve null si no hay param mesa', () {
      expect(parseMesaIdFromQr('https://tienda.vendia.store/x'), isNull);
      expect(parseMesaIdFromQr('https://tienda.vendia.store/x?sede=s1'), isNull);
    });

    test('devuelve null para basura o vacío', () {
      expect(parseMesaIdFromQr(''), isNull);
      expect(parseMesaIdFromQr('   '), isNull);
      expect(parseMesaIdFromQr('mesa-7'), isNull); // no es URL con ?mesa=
    });

    test('ignora mesa vacío', () {
      expect(parseMesaIdFromQr('https://tienda.vendia.store/x?mesa='), isNull);
    });
  });
}
