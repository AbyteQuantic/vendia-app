// Spec: specs/084-peluqueria-salon/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/screens/staff/liquidations_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._rows) : super(AuthService());
  final List<Map<String, dynamic>> _rows;

  @override
  Future<Map<String, dynamic>> getLiquidation({
    String? from,
    String? until,
    String? employeeUuid,
  }) async {
    return {'from': from, 'until': until, 'rows': _rows};
  }
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('formatCop', () {
    test('miles con punto y signo negativo', () {
      expect(formatCop(0), '\$0');
      expect(formatCop(1500), '\$1.500');
      expect(formatCop(1234567), '\$1.234.567');
      expect(formatCop(-6000), '-\$6.000');
    });
  });

  group('payModelLabel', () {
    test('traduce los modelos', () {
      expect(payModelLabel('commission'), 'Comisión por servicio');
      expect(payModelLabel('chair_rent'), 'Arriendo de silla');
      expect(payModelLabel(null), 'Sin esquema definido');
    });
  });

  testWidgets('estado vacío cuando no hay servicios atribuidos', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LiquidationsScreen(apiOverride: _FakeApi(const [])),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no hay servicios atribuidos'), findsOneWidget);
  });

  testWidgets('muestra una fila por profesional con su neto', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LiquidationsScreen(apiOverride: _FakeApi([
        {
          'employee_uuid': 'e1',
          'employee_name': 'Ana',
          'pay_model': 'commission',
          'payout': {
            'net_payout': 6400,
            'service_count': 2,
            'direction': 'to_pro',
            'commission_amount': 6400,
          },
        },
      ])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('\$6.400'), findsOneWidget);
    expect(find.textContaining('2 servicios'), findsOneWidget);
  });
}
