// Spec: specs/033-difusion-promociones/spec.md
//
// T-32 — Widget test de PromotionFormScreen.
// Cobertura:
//   - el formulario renderiza los campos del §4 (título, descripción,
//     foto, vigencia, mensaje, scheduling).
//   - validación: no se puede guardar sin título ni mensaje.
//   - crear una promoción con título + mensaje llama al backend y
//     devuelve la BroadcastPromotion.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/broadcast_promotion.dart';
import 'package:vendia_pos/screens/promotions/promotion_form_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — captura el payload de creación.
class _FakeFormApi extends ApiService {
  _FakeFormApi() : super(AuthService());

  Map<String, dynamic>? createdPayload;

  @override
  Future<Map<String, dynamic>> createBroadcastPromotion(
      Map<String, dynamic> data) async {
    createdPayload = data;
    return {
      'id': 'promo-new',
      'title': data['title'],
      'description': data['description'],
      'message_template': data['message_template'],
      'public_token': 'tok-new',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  testWidgets('renderiza los campos clave del formulario', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PromotionFormScreen(apiOverride: _FakeFormApi()),
    ));
    await tester.pumpAndSettle();

    // Visibles sin scroll.
    expect(find.byKey(const Key('promo_title')), findsOneWidget);
    expect(find.byKey(const Key('promo_description')), findsOneWidget);
    expect(find.byKey(const Key('promo_pick_image')), findsOneWidget);
    expect(find.byKey(const Key('promo_generate_banner')), findsOneWidget);

    // Más abajo en el ListView — el formulario los renderiza al
    // desplazarse.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_message_template')), 300,
        scrollable: list);
    expect(find.byKey(const Key('promo_message_template')), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_save_button')), 300,
        scrollable: list);
    expect(find.byKey(const Key('promo_save_button')), findsOneWidget);
  });

  testWidgets('ofrece los 3 presets de programación', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PromotionFormScreen(apiOverride: _FakeFormApi()),
    ));
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_schedule_now')), 300,
        scrollable: list);

    expect(find.byKey(const Key('promo_schedule_now')), findsOneWidget);
    expect(
        find.byKey(const Key('promo_schedule_tomorrow9am')), findsOneWidget);
    expect(find.byKey(const Key('promo_schedule_nextFriday6pm')),
        findsOneWidget);
  });

  testWidgets('no guarda sin título — la validación bloquea',
      (tester) async {
    final api = _FakeFormApi();
    await tester.pumpWidget(MaterialApp(
      home: PromotionFormScreen(apiOverride: api),
    ));
    await tester.pumpAndSettle();

    // El mensaje trae un default; el título arranca vacío.
    await tester.enterText(
        find.byKey(const Key('promo_title')), '   ');
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_save_button')), 300,
        scrollable: list);
    await tester.tap(find.byKey(const Key('promo_save_button')));
    await tester.pumpAndSettle();

    // La validación bloqueó el guardado — el backend no fue llamado.
    expect(api.createdPayload, isNull);

    // El mensaje de error del título aparece (volvemos a subir al campo).
    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_title')), -300,
        scrollable: list);
    expect(find.text('Escriba un título'), findsOneWidget);
  });

  testWidgets('crear una promoción válida llama al backend',
      (tester) async {
    final api = _FakeFormApi();
    BroadcastPromotion? returned;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                returned = await Navigator.of(context)
                    .push<BroadcastPromotion>(
                  MaterialPageRoute(
                    builder: (_) =>
                        PromotionFormScreen(apiOverride: api),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('promo_title')), '20% en kits de baño');

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_message_template')), 300,
        scrollable: list);
    await tester.enterText(
        find.byKey(const Key('promo_message_template')),
        'Hola {primer_nombre} 👋 promo');

    await tester.scrollUntilVisible(
        find.byKey(const Key('promo_save_button')), 300,
        scrollable: list);
    await tester.tap(find.byKey(const Key('promo_save_button')));
    await tester.pumpAndSettle();

    expect(api.createdPayload, isNotNull);
    expect(api.createdPayload!['title'], '20% en kits de baño');
    expect(returned, isNotNull);
    expect(returned!.id, 'promo-new');
  });
}
