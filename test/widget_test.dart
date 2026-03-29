import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/main.dart';

void main() {
  testWidgets('VendIA app smoke test — arranca sin errores',
      (WidgetTester tester) async {
    await tester.pumpWidget(const VendIAApp());
    // El splash (fondo primary) debe renderizarse mientras se verifica la sesión
    expect(find.text('VendIA'), findsOneWidget);
  });
}
