// Spec: specs/033-difusion-promociones/spec.md
//
// T-34 — Widget test de AudienceSelectorScreen.
// Cobertura:
//   - los 5 FilterChips RFM se renderizan.
//   - cambiar de FilterChip recarga la audiencia y actualiza el
//     contador en vivo.
//   - el banner del asistente de tamaño aparece según la cantidad.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/promotions/audience_selector_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — devuelve una cantidad de clientes distinta por
/// filtro RFM para verificar que el contador cambia.
class _FakeAudienceApi extends ApiService {
  _FakeAudienceApi() : super(AuthService());

  /// Cantidad de candidatos que devuelve cada filtro.
  static const _countsByFilter = <String, int>{
    'all': 5,
    'frequent': 2,
    'vip': 1,
    'dormant': 3,
    'recent': 2,
    'manual': 5,
  };

  @override
  Future<Map<String, dynamic>> fetchPromotionAudience(
    String promotionId, {
    required String filter,
    List<String>? customerIds,
  }) async {
    final count = _countsByFilter[filter] ?? 0;
    return {
      'data': List.generate(
        count,
        (i) => {
          'id': '$filter-cust-$i',
          'name': 'Cliente $i',
          'phone': '30012345$i$i',
        },
      ),
      'meta': {'count': count},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  Widget wrap() => MaterialApp(
        home: AudienceSelectorScreen(
          promotionId: 'promo-1',
          apiOverride: _FakeAudienceApi(),
        ),
      );

  testWidgets('renderiza los 5 FilterChips RFM + el de selección manual',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('audience_filter_all')), findsOneWidget);
    expect(
        find.byKey(const Key('audience_filter_frequent')), findsOneWidget);
    expect(find.byKey(const Key('audience_filter_vip')), findsOneWidget);
    expect(
        find.byKey(const Key('audience_filter_dormant')), findsOneWidget);
    expect(find.byKey(const Key('audience_filter_recent')), findsOneWidget);
    expect(find.byKey(const Key('audience_filter_manual')), findsOneWidget);
  });

  testWidgets('el contador arranca con la audiencia "Todos" (5 clientes)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(
      find.text('Audiencia: 5 clientes seleccionados'),
      findsOneWidget,
    );
  });

  testWidgets('cambiar el FilterChip recarga la audiencia y el contador',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Empieza en "Todos" → 5.
    expect(
        find.text('Audiencia: 5 clientes seleccionados'), findsOneWidget);

    // Toca "Frecuentes" → el contador baja a 2.
    await tester.tap(find.byKey(const Key('audience_filter_frequent')));
    await tester.pumpAndSettle();
    expect(
        find.text('Audiencia: 2 clientes seleccionados'), findsOneWidget);

    // Toca "VIP" → el contador baja a 1 (singular).
    await tester.tap(find.byKey(const Key('audience_filter_vip')));
    await tester.pumpAndSettle();
    expect(
        find.text('Audiencia: 1 cliente seleccionado'), findsOneWidget);
  });

  testWidgets('el banner del asistente de tamaño aparece con audiencia',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('audience_size_advisor')), findsOneWidget);
  });

  testWidgets('el botón confirmar lleva el conteo de la audiencia',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('audience_confirm')), findsOneWidget);
    expect(find.text('Continuar con 5 clientes'), findsOneWidget);
  });
}
