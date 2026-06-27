// Spec: specs/083-mesas-catalogo-qr/spec.md
//
// El área de una mesa se normaliza para EVITAR DUPLICADOS por tildes, mayúsculas,
// espacios o typos de espaciado. foldAreaKey es la clave de comparación.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/dashboard/table_floor_plan_screen.dart';

void main() {
  group('foldAreaKey — clave anti-duplicados de área', () {
    test('mayúsculas/minúsculas se consideran la misma área', () {
      expect(foldAreaKey('Terraza'), foldAreaKey('terraza'));
      expect(foldAreaKey('SALÓN'), foldAreaKey('salon'));
    });

    test('tildes y espacios extra no crean áreas distintas', () {
      expect(foldAreaKey('Salón'), foldAreaKey('Salon'));
      expect(foldAreaKey('  Terraza  '), foldAreaKey('Terraza'));
      expect(foldAreaKey('Zona   VIP'), foldAreaKey('Zona VIP'));
    });

    test('áreas realmente distintas NO colisionan', () {
      expect(foldAreaKey('Terraza') == foldAreaKey('Salón'), isFalse);
      expect(foldAreaKey('Barra') == foldAreaKey('Balcón'), isFalse);
    });

    test('vacío y solo-espacios producen clave vacía', () {
      expect(foldAreaKey(''), '');
      expect(foldAreaKey('   '), '');
    });
  });
}
