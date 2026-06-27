// Spec: specs/083-mesas-catalogo-qr/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/text_normalize.dart';

void main() {
  group('foldKey', () {
    test('ignora mayúsculas, tildes y espacios', () {
      expect(foldKey('Gaseosas'), foldKey('gaseosas'));
      expect(foldKey('Café'), foldKey('cafe'));
      expect(foldKey('  Aseo  '), foldKey('Aseo'));
      expect(foldKey('Frutas   y Verduras'), foldKey('frutas y verduras'));
    });
    test('valores distintos no colisionan', () {
      expect(foldKey('Aseo') == foldKey('Granos'), isFalse);
    });
    test('vacío/espacios → clave vacía', () {
      expect(foldKey(''), '');
      expect(foldKey('   '), '');
    });
  });

  group('canonicalValue — reutiliza la grafía existente (anti-duplicado)', () {
    const existing = ['Gaseosas', 'Aseo', 'Café'];

    test('escribir una variante reusa la grafía canónica existente', () {
      expect(canonicalValue('gaseosas', existing), 'Gaseosas');
      expect(canonicalValue('  ASEO ', existing), 'Aseo');
      expect(canonicalValue('cafe', existing), 'Café'); // tildes
    });

    test('valor nuevo se conserva tal cual (trim)', () {
      expect(canonicalValue('  Licores ', existing), 'Licores');
    });

    test('vacío → vacío', () {
      expect(canonicalValue('   ', existing), '');
    });
  });
}
