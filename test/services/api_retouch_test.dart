// Spec: specs/101-retocar-fotos-inventario/spec.md (T-22/T-23, FR-11, FR-14,
// FR-15)
//
// Métodos de ApiService para la cola de retoque en segundo plano:
// createRetouchBatch / fetchRetouchSummary / confirmRetouchItems /
// discardRetouchItems / cancelRetouchBatch. Contrato del plan §4. Los errores
// viajan como AppError (mensaje en español, jamás el tipo crudo).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Adaptador que registra la última petición y responde con un payload fijo.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.statusCode, this.payload);
  final int statusCode;
  final String payload;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(payload, statusCode, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? null : <String, String>{},
    );
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  ApiService apiWith(_RecordingAdapter adapter) {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = adapter;
    return api;
  }

  group('createRetouchBatch', () {
    test('202 devuelve batch_id, queued_count y skipped', () async {
      final adapter = _RecordingAdapter(
          202,
          '{"data":{"batch_id":"b1","queued_count":3,'
          '"skipped":[{"product_id":"p9","reason":"stale"}]}}');
      final api = apiWith(adapter);

      final result = await api.createRetouchBatch(productIds: ['p1', 'p2']);

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path,
          contains('/api/v1/inventory/retouch/batches'));
      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body['product_ids'], ['p1', 'p2']);
      expect(result['batch_id'], 'b1');
      expect(result['queued_count'], 3);
      expect(result['skipped'], isA<List<dynamic>>());
    });

    test('sin product_ids el body no manda la llave (vacío = todos)',
        () async {
      final adapter = _RecordingAdapter(
          202, '{"data":{"batch_id":"b1","queued_count":8,"skipped":[]}}');
      final api = apiWith(adapter);

      await api.createRetouchBatch();

      final body = adapter.lastRequest!.data as Map<String, dynamic>;
      expect(body.containsKey('product_ids'), isFalse);
    });

    test('500 lanza AppError con mensaje en español', () async {
      final api = apiWith(_RecordingAdapter(500, '{"error":"boom"}'));
      expect(
        () => api.createRetouchBatch(productIds: ['p1']),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('fetchRetouchSummary', () {
    test('pagina review_items: manda page y per_page=100 por defecto',
        () async {
      final adapter = _RecordingAdapter(200,
          '{"data":{"eligible_count":0,"active_batch":null,"review_items":[]}}');
      final api = apiWith(adapter);

      await api.fetchRetouchSummary();
      expect(adapter.lastRequest!.uri.queryParameters['page'], '1');
      expect(adapter.lastRequest!.uri.queryParameters['per_page'], '100');

      await api.fetchRetouchSummary(page: 3, perPage: 50);
      expect(adapter.lastRequest!.uri.queryParameters['page'], '3');
      expect(adapter.lastRequest!.uri.queryParameters['per_page'], '50');
    });

    test('parsea eligible_count, active_batch y review_items', () async {
      final payload = jsonEncode({
        'data': {
          'eligible_count': 5,
          'active_batch': {
            'id': 'b1',
            'status': 'running',
            'queued': 2,
            'processed': 3,
            'failed': 0,
            'ready_for_review': 3,
          },
          'review_items': [
            {
              'item_id': 'i1',
              'product_id': 'p1',
              'name': 'Arroz',
              'original_url': 'https://x/products/t/a.jpg',
              'candidate_url': 'https://x/products/t/a-enhanced.jpg',
            }
          ],
        }
      });
      final adapter = _RecordingAdapter(200, payload);
      final api = apiWith(adapter);

      final summary = await api.fetchRetouchSummary();

      expect(adapter.lastRequest!.method, 'GET');
      expect(adapter.lastRequest!.path,
          contains('/api/v1/inventory/retouch/summary'));
      expect(summary['eligible_count'], 5);
      expect((summary['active_batch'] as Map)['ready_for_review'], 3);
      expect((summary['review_items'] as List).single['item_id'], 'i1');
    });

    test('active_batch null (sin lote) no rompe', () async {
      final api = apiWith(_RecordingAdapter(200,
          '{"data":{"eligible_count":0,"active_batch":null,"review_items":[]}}'));
      final summary = await api.fetchRetouchSummary();
      expect(summary['active_batch'], isNull);
    });
  });

  group('confirm / discard / cancel', () {
    test('confirmRetouchItems manda item_ids al endpoint de confirm',
        () async {
      final adapter =
          _RecordingAdapter(200, '{"data":{"confirmed":2}}');
      final api = apiWith(adapter);

      await api.confirmRetouchItems(['i1', 'i2']);

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path,
          contains('/api/v1/inventory/retouch/items/confirm'));
      expect((adapter.lastRequest!.data as Map)['item_ids'], ['i1', 'i2']);
    });

    test('discardRetouchItems manda item_ids al endpoint de discard',
        () async {
      final adapter =
          _RecordingAdapter(200, '{"data":{"discarded":1}}');
      final api = apiWith(adapter);

      await api.discardRetouchItems(['i1']);

      expect(adapter.lastRequest!.path,
          contains('/api/v1/inventory/retouch/items/discard'));
      expect((adapter.lastRequest!.data as Map)['item_ids'], ['i1']);
    });

    test('cancelRetouchBatch pega al endpoint del lote', () async {
      final adapter = _RecordingAdapter(200, '{"data":{"canceled":true}}');
      final api = apiWith(adapter);

      await api.cancelRetouchBatch('b1');

      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.path,
          contains('/api/v1/inventory/retouch/batches/b1/cancel'));
    });

    test('errores de red se traducen a AppError', () async {
      final api = apiWith(_RecordingAdapter(503, '{"error":"caída"}'));
      expect(() => api.confirmRetouchItems(['i1']), throwsA(isA<AppError>()));
      expect(() => api.discardRetouchItems(['i1']), throwsA(isA<AppError>()));
      expect(() => api.cancelRetouchBatch('b1'), throwsA(isA<AppError>()));
    });
  });
}
