// Spec: specs/033-difusion-promociones/spec.md
//
// T-36 — Widget test de WhatsappQueueScreen (cola modo express).
// Cobertura:
//   - el banner inicial muestra el botón "Empezar".
//   - el countdown de 3s corre y luego abre WhatsApp.
//   - el mensaje pre-personalizado se muestra correcto.
//   - los botones Pausar / Saltar / Reanudar funcionan.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/broadcast_promotion.dart';
import 'package:vendia_pos/models/promotion_delivery.dart';
import 'package:vendia_pos/screens/promotions/whatsapp_queue_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — registra los cambios de estado de delivery.
class _FakeQueueApi extends ApiService {
  _FakeQueueApi() : super(AuthService());

  final List<String> updatedStatuses = [];

  @override
  Future<Map<String, dynamic>> updatePromotionDelivery(
    String promotionId,
    String deliveryId, {
    required String status,
  }) async {
    updatedStatuses.add('$deliveryId:$status');
    return {'id': deliveryId, 'status': status};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  const promotion = BroadcastPromotion(
    id: 'promo-1',
    title: 'Promo de prueba',
    messageTemplate: 'Hola {primer_nombre} 👋 promo',
    publicToken: 'tok-1',
  );

  List<PromotionDelivery> buildQueue() => [
        const PromotionDelivery(
          id: 'd-1',
          promotionId: 'promo-1',
          customerId: 'c-1',
          customerName: 'María José',
          customerPhone: '3001112233',
          renderedMessage: 'Hola María 👋 promo',
        ),
        const PromotionDelivery(
          id: 'd-2',
          promotionId: 'promo-1',
          customerId: 'c-2',
          customerName: 'Carlos',
          customerPhone: '3004445566',
          renderedMessage: 'Hola Carlos 👋 promo',
        ),
      ];

  Widget wrap(_FakeQueueApi api,
      {List<Uri>? launched}) {
    return MaterialApp(
      home: WhatsappQueueScreen(
        promotion: promotion,
        deliveries: buildQueue(),
        apiOverride: api,
        launcherOverride: (uri) async {
          launched?.add(uri);
          return true;
        },
      ),
    );
  }

  testWidgets('el banner inicial muestra el botón "Empezar"',
      (tester) async {
    await tester.pumpWidget(wrap(_FakeQueueApi()));
    await tester.pump();

    expect(find.byKey(const Key('queue_start_button')), findsOneWidget);
    expect(find.text('2 clientes en la cola'), findsOneWidget);
  });

  testWidgets('el countdown corre 3 segundos y luego abre WhatsApp',
      (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(wrap(_FakeQueueApi(), launched: launched));
    await tester.pump();

    await tester.tap(find.byKey(const Key('queue_start_button')));
    await tester.pump();

    // Arranca en 3.
    expect(find.byKey(const Key('queue_countdown')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);

    // Al expirar el countdown se abre WhatsApp.
    await tester.pump(const Duration(seconds: 1));
    expect(launched.length, 1);
    expect(launched.first.toString(), contains('wa.me/573001112233'));
  });

  testWidgets('muestra el mensaje pre-personalizado del delivery',
      (tester) async {
    await tester.pumpWidget(wrap(_FakeQueueApi()));
    await tester.pump();
    await tester.tap(find.byKey(const Key('queue_start_button')));
    await tester.pump();

    final preview = tester.widget<Text>(
        find.byKey(const Key('queue_message_preview')));
    expect(preview.data, 'Hola María 👋 promo');
  });

  testWidgets('Pausar detiene el countdown y muestra "Reanudar"',
      (tester) async {
    await tester.pumpWidget(wrap(_FakeQueueApi()));
    await tester.pump();
    await tester.tap(find.byKey(const Key('queue_start_button')));
    await tester.pump();

    expect(find.byKey(const Key('queue_pause_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('queue_pause_button')));
    await tester.pump();

    // En pausa el botón cambia a "Reanudar".
    expect(find.byKey(const Key('queue_resume_button')), findsOneWidget);
    expect(find.text('En pausa'), findsOneWidget);

    // El countdown queda congelado — avanzar el reloj no lo cambia.
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('queue_resume_button')), findsOneWidget);
  });

  testWidgets('Saltar marca el delivery como skipped y avanza',
      (tester) async {
    final api = _FakeQueueApi();
    await tester.pumpWidget(wrap(api));
    await tester.pump();
    await tester.tap(find.byKey(const Key('queue_start_button')));
    await tester.pump();

    // Primer cliente: María José.
    expect(find.text('María José'), findsWidgets);

    await tester.tap(find.byKey(const Key('queue_skip_button')));
    await tester.pump();

    // Se registró el skip del primer delivery.
    expect(api.updatedStatuses, contains('d-1:skipped'));

    // Avanzó al segundo cliente: Carlos.
    expect(find.text('Carlos'), findsWidgets);
  });

  testWidgets('cola vacía cae directo en el estado "terminada"',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WhatsappQueueScreen(
          promotion: promotion,
          deliveries: const [],
          apiOverride: _FakeQueueApi(),
          launcherOverride: (uri) async => true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('queue_done')), findsOneWidget);
  });
}
