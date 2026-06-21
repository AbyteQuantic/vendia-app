// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/money.dart';
void main() {
  test('formato COP con separador de miles', () {
    expect(copMoney(1700), r'$1.700');
    expect(copMoney(1234567), r'$1.234.567');
    expect(copMoney(0), r'$0');
    expect(copMoney(8400.6), r'$8.401');
  });
}
