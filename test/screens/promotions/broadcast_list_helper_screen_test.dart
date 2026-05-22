// Spec: specs/033-difusion-promociones/spec.md
//
// Test del generador de vCard del asistente de Lista de Difusión
// (F033 — AC-06b). Cubre la función pura `buildVCard`.

import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/customer.dart';
import 'package:vendia_pos/screens/promotions/broadcast_list_helper_screen.dart';

void main() {
  group('buildVCard', () {
    test('genera una tarjeta VCARD por cada cliente con teléfono', () {
      final vcard = buildVCard(const [
        Customer(id: '1', name: 'María Pérez', phone: '3001112233'),
        Customer(id: '2', name: 'Carlos Ruiz', phone: '3004445566'),
      ]);
      expect('BEGIN:VCARD'.allMatches(vcard).length, 2);
      expect('END:VCARD'.allMatches(vcard).length, 2);
      expect(vcard, contains('FN:María Pérez'));
      expect(vcard, contains('TEL;TYPE=CELL:3001112233'));
      expect(vcard, contains('TEL;TYPE=CELL:3004445566'));
    });

    test('omite los clientes sin teléfono', () {
      final vcard = buildVCard(const [
        Customer(id: '1', name: 'Con Teléfono', phone: '3001112233'),
        Customer(id: '2', name: 'Sin Teléfono', phone: ''),
        Customer(id: '3', name: 'Espacios', phone: '   '),
      ]);
      expect('BEGIN:VCARD'.allMatches(vcard).length, 1);
      expect(vcard, contains('FN:Con Teléfono'));
      expect(vcard, isNot(contains('Sin Teléfono')));
    });

    test('usa "Cliente" como nombre cuando el cliente no tiene nombre', () {
      final vcard = buildVCard(const [
        Customer(id: '1', name: '', phone: '3001112233'),
      ]);
      expect(vcard, contains('FN:Cliente'));
    });

    test('lista vacía produce una cadena vacía', () {
      expect(buildVCard(const []), '');
    });
  });
}
