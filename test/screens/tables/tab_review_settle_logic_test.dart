// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/tables/tab_review_screen.dart';

void main() {
  group('isAccountFullyPaid', () {
    test('saldada cuando hubo abonos y el saldo es ~0', () {
      expect(isAccountFullyPaid(paid: 71450, remaining: 0), isTrue);
      expect(isAccountFullyPaid(paid: 71450, remaining: 0.4), isTrue); // centavos
    });
    test('NO saldada con saldo pendiente', () {
      expect(isAccountFullyPaid(paid: 10000, remaining: 61450), isFalse);
    });
    test('NO saldada si no hubo abonos (cuenta vacía/nueva)', () {
      expect(isAccountFullyPaid(paid: 0, remaining: 0), isFalse);
    });
  });

  group('dominantAbonoMethod', () {
    test('un solo método → ese método (no "multi")', () {
      expect(dominantAbonoMethod([
        {'payment_method': 'Nequi'},
        {'payment_method': 'Nequi'},
      ]), 'Nequi');
    });
    test('métodos distintos → Mixto', () {
      expect(dominantAbonoMethod([
        {'payment_method': 'Efectivo'},
        {'payment_method': 'Nequi'},
      ]), 'Mixto');
    });
    test('sin método → Efectivo', () {
      expect(dominantAbonoMethod([]), 'Efectivo');
    });
  });
}
