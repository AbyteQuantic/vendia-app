import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/screens/pos/cart_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('clearContextForLabel resets matching mesa back to mostrador',
      () async {
    final c = CartController();
    c.setContext(const AccountContext(
        type: AccountType.mesa, tableLabel: 'Mesa 3'));
    expect(c.activeContext.type, AccountType.mesa);

    c.clearContextForLabel('Mesa 3');

    final stillMesa3 = List.generate(10, (i) => c.contextAt(i))
        .where((ctx) =>
            (ctx.type == AccountType.mesa ||
                ctx.type == AccountType.mesaInmediata) &&
            ctx.tableLabel == 'Mesa 3');
    expect(stillMesa3, isEmpty);
  });

  test('clearContextForLabel is a no-op for unknown label', () async {
    final c = CartController();
    c.setContext(const AccountContext(
        type: AccountType.mesa, tableLabel: 'Mesa 1'));
    c.clearContextForLabel('Mesa 99');
    expect(c.activeContext.tableLabel, 'Mesa 1');
  });
}
