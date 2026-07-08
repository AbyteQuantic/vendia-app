// Spec: specs/101-retocar-fotos-inventario/spec.md (T-24/T-25, FR-04, FR-05,
// FR-06, FR-08, FR-11, FR-14, FR-15, AC-03, AC-05, AC-06, AC-09, AC-10)
//
// RetouchCompletionScreen: TODO retoque pasa por la cola del backend
// (decisión del concilio + corrección de diseño): "Mejorar foto" individual
// encola un LOTE DE 1 (POST /retouch/batches {product_ids:[id]}), el
// resultado llega como review_item del summary y el tendero confirma o
// descarta — nada se aplica solo (candidate_url nunca pisa la foto). El lote
// completo usa el mismo camino con confirmación previa, banner de progreso
// sin ansiedad y "Aplicar las N".

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/retouch_completion_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

const _raw1 = 'https://r2.vendia.store/products/t1/aaa.jpg';
const _raw2 = 'https://r2.vendia.store/products/t1/bbb.jpg';
const _cand1 = 'https://r2.vendia.store/products/t1/aaa-enhanced.jpg';
const _cand2 = 'https://r2.vendia.store/products/t1/bbb-enhanced.jpg';

Map<String, dynamic> _emptySummary() => {
      'eligible_count': 0,
      'active_batch': null,
      'review_items': <Map<String, dynamic>>[],
    };

Map<String, dynamic> _reviewItem(String itemId, String productId, String name,
        String original, String candidate) =>
    {
      'item_id': itemId,
      'product_id': productId,
      'name': name,
      'original_url': original,
      'candidate_url': candidate,
    };

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  Map<String, dynamic> summary = _emptySummary();
  final List<List<String>?> createCalls = [];
  final List<List<String>> confirmCalls = [];
  final List<List<String>> discardCalls = [];
  final List<String> cancelCalls = [];
  AppError? createError;
  AppError? confirmError;

  /// Qué summary devolver DESPUÉS de crear un lote (simula al worker).
  Map<String, dynamic>? summaryAfterCreate;

  @override
  Future<Map<String, dynamic>> createRetouchBatch(
      {List<String>? productIds}) async {
    createCalls.add(productIds);
    final err = createError;
    if (err != null) throw err;
    if (summaryAfterCreate != null) summary = summaryAfterCreate!;
    return {
      'batch_id': 'b1',
      'queued_count': productIds?.length ?? 0,
      'skipped': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRetouchSummary() async => summary;

  @override
  Future<void> confirmRetouchItems(List<String> itemIds) async {
    final err = confirmError;
    if (err != null) throw err;
    confirmCalls.add(itemIds);
  }

  @override
  Future<void> discardRetouchItems(List<String> itemIds) async {
    discardCalls.add(itemIds);
  }

  @override
  Future<void> cancelRetouchBatch(String batchId) async {
    cancelCalls.add(batchId);
  }
}

Map<String, dynamic> _p(String id, String name, String photoUrl) => {
      'id': id,
      'name': name,
      'price': 2500,
      'stock': 3,
      'photo_url': photoUrl,
      'image_url': '',
    };

List<Map<String, dynamic>> _twoProducts() => [
      _p('1', 'Arroz Diana', _raw1),
      _p('2', 'Panela Real', _raw2),
    ];

Future<void> _pumpScreen(WidgetTester tester, _FakeApi api,
    List<Map<String, dynamic>> products) async {
  await tester.pumpWidget(MaterialApp(
    home: RetouchCompletionScreen(
      products: products,
      apiOverride: api,
      pollInterval: const Duration(minutes: 5),
    ),
  ));
  await tester.pump(); // build
  await tester.pump(); // summary inicial resuelto
}

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('muestra las tarjetas prefiltradas con nombre, precio y la '
      'acción única "Mejorar foto" (FR-04)', (tester) async {
    final api = _FakeApi();
    await _pumpScreen(tester, api, _twoProducts());

    expect(find.text('Arroz Diana'), findsOneWidget);
    expect(find.text('Panela Real'), findsOneWidget);
    expect(find.text('\$2.500'), findsNWidgets(2));
    expect(find.text('Mejorar foto'), findsNWidgets(2));
    expect(find.text('Retocar todas (2)'), findsOneWidget);
  });

  testWidgets('"Mejorar foto" encola un lote de 1 y el resultado llega como '
      'revisión antes/después (AC-03)', (tester) async {
    final api = _FakeApi();
    api.summaryAfterCreate = {
      'eligible_count': 1,
      'active_batch': null, // lote de 1 ya procesado: solo queda revisar
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
      ],
    };
    await _pumpScreen(tester, api, _twoProducts());

    await tester.tap(find.text('Mejorar foto').first);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.createCalls.single, ['1']);
    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Después'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    // La tarjeta pendiente de Arroz salió; queda solo la de Panela.
    expect(find.text('Mejorar foto'), findsOneWidget);
  });

  testWidgets('Confirmar aplica el candidato y la tarjeta sale (FR-06)',
      (tester) async {
    final api = _FakeApi();
    api.summary = {
      'eligible_count': 2,
      'active_batch': null,
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
      ],
    };
    await _pumpScreen(tester, api, _twoProducts());

    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.confirmCalls.single, ['i1']);
    expect(find.text('Confirmar'), findsNothing);
    // Arroz quedó retocado: ya no ofrece "Mejorar foto".
    expect(find.text('Mejorar foto'), findsOneWidget);
  });

  testWidgets('Descartar deja el producto pendiente otra vez y su foto '
      'intacta (AC-06)', (tester) async {
    final api = _FakeApi();
    api.summary = {
      'eligible_count': 2,
      'active_batch': null,
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
      ],
    };
    await _pumpScreen(tester, api, _twoProducts());
    expect(find.text('Mejorar foto'), findsOneWidget); // solo Panela

    await tester.tap(find.text('Descartar'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.discardCalls.single, ['i1']);
    // Arroz vuelve a la lista de pendientes (sigue contando como sin retocar).
    expect(find.text('Mejorar foto'), findsNWidgets(2));
    expect(find.text('Confirmar'), findsNothing);
  });

  testWidgets('"Retocar todas (N)" pide confirmación con el número, encola y '
      'muestra progreso sin ansiedad + cancelar discreto (FR-11/FR-15)',
      (tester) async {
    final api = _FakeApi();
    api.summaryAfterCreate = {
      'eligible_count': 2,
      'active_batch': {
        'id': 'b1',
        'status': 'running',
        'queued': 1,
        'processed': 1,
        'failed': 0,
        'ready_for_review': 1,
      },
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
      ],
    };
    await _pumpScreen(tester, api, _twoProducts());

    await tester.tap(find.text('Retocar todas (2)'));
    await tester.pumpAndSettle();
    // Sheet de confirmación con el número.
    expect(find.text('Retocar 2 fotos'), findsOneWidget);
    await tester.tap(find.text('Retocar 2 fotos'));
    await tester.pumpAndSettle();

    expect(api.createCalls.single, ['1', '2']);
    // Banner de progreso sin ansiedad (D5).
    expect(
        find.textContaining('La IA sigue con las demás'), findsOneWidget);
    expect(find.textContaining('1 lista'), findsOneWidget);
    // El ítem listo aparece ARRIBA para revisar mientras el lote corre.
    expect(find.text('Confirmar'), findsOneWidget);
    // Cancelar el lote es una acción secundaria discreta.
    await tester.tap(find.text('Cancelar lote'));
    await tester.pump();
    await tester.pump();
    expect(api.cancelCalls.single, 'b1');
  });

  testWidgets('pausa del lote: banner calmado, sin la palabra "error" y sin '
      'botón de reintento (AC-10)', (tester) async {
    final api = _FakeApi();
    api.summary = {
      'eligible_count': 2,
      'active_batch': {
        'id': 'b1',
        'status': 'paused_error',
        'queued': 2,
        'processed': 0,
        'failed': 0,
        'ready_for_review': 0,
      },
      'review_items': <Map<String, dynamic>>[],
    };
    await _pumpScreen(tester, api, _twoProducts());

    expect(find.text('La IA está ocupada un momento. Seguirá sola.'),
        findsOneWidget);
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('Error'), findsNothing);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('"Aplicar las N" confirma todo lo revisable en un solo sheet '
      '(FR-14)', (tester) async {
    final api = _FakeApi();
    api.summary = {
      'eligible_count': 2,
      'active_batch': null,
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
        _reviewItem('i2', '2', 'Panela Real', _raw2, _cand2),
      ],
    };
    await _pumpScreen(tester, api, _twoProducts());

    await tester.tap(find.text('Aplicar las 2'));
    await tester.pumpAndSettle();
    // Un solo sheet de confirmación masiva.
    expect(find.text('Aplicar 2 fotos'), findsOneWidget);
    await tester.tap(find.text('Aplicar 2 fotos'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.confirmCalls.single, ['i1', 'i2']);
    expect(find.text('Confirmar'), findsNothing);
  });

  testWidgets('estado vacío celebratorio cuando no queda nada', (tester) async {
    final api = _FakeApi();
    await _pumpScreen(tester, api, const []);

    expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);
    expect(find.text('Volver al inventario'), findsOneWidget);
  });

  testWidgets('error de red al encolar: banner honesto + Reintentar; la '
      'tarjeta no se marca hecha (AC-05/FR-08)', (tester) async {
    final api = _FakeApi();
    api.createError = const AppError(
      type: AppErrorType.network,
      message: 'No pudimos conectar. Revisa tu internet e intenta de nuevo.',
    );
    await _pumpScreen(tester, api, _twoProducts());

    await tester.tap(find.text('Mejorar foto').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Mejorar foto'), findsNWidgets(2)); // nada se marcó

    // Vuelve la señal: Reintentar encola de verdad.
    api.createError = null;
    api.summaryAfterCreate = {
      'eligible_count': 2,
      'active_batch': null,
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
      ],
    };
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.createCalls.length, 2);
    expect(find.text('Confirmar'), findsOneWidget);
  });

  testWidgets('un lote activo de otra sesión se retoma al abrir (AC-09)',
      (tester) async {
    final api = _FakeApi();
    api.summary = {
      'eligible_count': 2,
      'active_batch': {
        'id': 'b7',
        'status': 'running',
        'queued': 8,
        'processed': 12,
        'failed': 0,
        'ready_for_review': 12,
      },
      'review_items': [
        _reviewItem('i1', '1', 'Arroz Diana', _raw1, _cand1),
      ],
    };
    await _pumpScreen(tester, api, _twoProducts());

    expect(find.textContaining('12 listas'), findsOneWidget);
    expect(find.textContaining('La IA sigue con las demás'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
  });
}
