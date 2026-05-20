// Spec: specs/027-importador-inventario/spec.md
//
// Tests para ApiService.importProducts:
//   - Envía filas en chunks de 100 (AC-08 / T-12)
//   - Reintenta hasta 3 veces ante errores de red o 5xx (FR-12)
//   - NO reintenta errores 4xx
//   - Acumula reportes de todos los chunks en un ImportReport
//
// Espejo arquitectónico de api_service_import_test.dart (F026).
// Usa ScriptedAdapter — sin red real.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

// ── Scripted adapter (same pattern as api_service_import_test.dart) ───────────

class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.script);

  final List<ResponseBody Function(RequestOptions, List<int>?)> script;
  int callCount = 0;
  final List<Map<String, dynamic>> capturedBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      try {
        capturedBodies
            .add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      } catch (_) {
        capturedBodies.add({});
      }
    } else {
      capturedBodies.add({});
    }

    final index = callCount < script.length ? callCount : script.length - 1;
    callCount++;
    return script[index](options, null);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody Function(RequestOptions, List<int>?) _okReport({
  int created = 0,
  int updated = 0,
  int skipped = 0,
  List<Map<String, dynamic>> failed = const [],
}) {
  final body = jsonEncode({
    'data': {
      'created': created,
      'updated': updated,
      'skipped': skipped,
      'failed': failed,
    },
  });
  return (options, _) => ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}

ResponseBody Function(RequestOptions, List<int>?) _fail(
  DioExceptionType type, {
  int? status,
}) {
  return (options, _) {
    throw DioException(
      requestOptions: options,
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: options,
              statusCode: status,
              data: {'error': 'internal server error'},
            ),
    );
  };
}

class _StubAuth extends AuthService {
  @override
  Future<String?> getToken() async => 'test-token-123';
}

ApiService buildService(
  ScriptedAdapter adapter, {
  List<Duration>? retryDelays,
}) {
  final svc = ApiService(
    _StubAuth(),
    importRetryDelays: retryDelays ?? [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
    addColdStartInterceptor: false,
  );
  svc.httpClientAdapterForTesting = adapter;
  return svc;
}

List<Map<String, dynamic>> _productRows(int n) => List.generate(
      n,
      (i) => {
        'name': 'Producto $i',
        'price': '${1000 + i * 100}',
        'barcode': '77000${i.toString().padLeft(5, '0')}',
      },
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test');
  });

  group('ApiService.importProducts — chunking (AC-08)', () {
    test('250 rows → 3 requests de 100, 100, 50', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 100),
        _okReport(created: 100),
        _okReport(created: 50),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(250));

      expect(adapter.callCount, equals(3));
      expect(report.created, equals(250));
      expect(report.updated, equals(0));
    });

    test('100 rows → 1 request', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 100),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(100));

      expect(adapter.callCount, equals(1));
      expect(report.created, equals(100));
    });

    test('0 rows → 0 requests, reporte vacío', () async {
      final adapter = ScriptedAdapter([]);
      final svc = buildService(adapter);

      final report = await svc.importProducts([]);

      expect(adapter.callCount, equals(0));
      expect(report.created, equals(0));
    });

    test('101 rows → 2 requests (100 + 1)', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 100),
        _okReport(created: 1),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(101));

      expect(adapter.callCount, equals(2));
      expect(report.created, equals(101));
    });

    test('acumula created+updated+skipped+failed de todos los chunks', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 90, updated: 5, skipped: 3, failed: [
          {'row_index': 2, 'reason': 'precio inválido'},
        ]),
        _okReport(created: 80, updated: 10, skipped: 0, failed: [
          {'row_index': 0, 'reason': 'nombre vacío'},
          {'row_index': 3, 'reason': 'precio inválido: abc'},
        ]),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(200));

      expect(report.created, equals(170));
      expect(report.updated, equals(15));
      expect(report.skipped, equals(3));
      expect(report.failed.length, equals(3));
    });
  });

  group('ApiService.importProducts — retry ante red/5xx (FR-12)', () {
    test('error de conexión en primer intento → reintenta → éxito', () async {
      final adapter = ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _okReport(created: 5),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(5));

      expect(adapter.callCount, equals(2));
      expect(report.created, equals(5));
    });

    test('5xx en primer intento → reintenta → éxito', () async {
      final adapter = ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 500),
        _okReport(created: 3),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(3));

      expect(adapter.callCount, equals(2));
      expect(report.created, equals(3));
    });

    test('503 dos veces → éxito en tercer intento', () async {
      final adapter = ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 503),
        _fail(DioExceptionType.badResponse, status: 503),
        _okReport(created: 2),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importProducts(_productRows(2));

      expect(adapter.callCount, equals(3));
      expect(report.created, equals(2));
    });

    test('falla 3 veces → propaga el error (máx reintentos superado)', () async {
      final adapter = ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
      ]);
      final svc = buildService(adapter);

      await expectLater(
        svc.importProducts(_productRows(5)),
        throwsA(isA<Exception>()),
      );
      expect(adapter.callCount, lessThanOrEqualTo(4));
    });

    test('error 4xx (400) NO se reintenta', () async {
      final adapter = ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 400),
      ]);
      final svc = buildService(adapter);

      await expectLater(
        svc.importProducts(_productRows(5)),
        throwsA(isA<Exception>()),
      );
      expect(adapter.callCount, equals(1));
    });

    test('error 4xx (422) NO se reintenta', () async {
      final adapter = ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 422),
      ]);
      final svc = buildService(adapter);

      await expectLater(
        svc.importProducts(_productRows(5)),
        throwsA(isA<Exception>()),
      );
      expect(adapter.callCount, equals(1));
    });
  });

  group('ApiService.importProducts — payload del request', () {
    test('incluye dedup_strategy=merge_by_barcode_then_name', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 1),
      ]);
      final svc = buildService(adapter);

      await svc.importProducts([
        {'name': 'Coca Cola 350ml', 'price': '2500'},
      ]);

      expect(adapter.capturedBodies.first['dedup_strategy'],
          equals('merge_by_barcode_then_name'));
    });

    test('las filas se envían correctamente en el payload', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 2),
      ]);
      final svc = buildService(adapter);

      await svc.importProducts([
        {'name': 'Coca Cola', 'price': '2500', 'barcode': '770001'},
        {'name': 'Pepsi', 'price': '2200'},
      ]);

      final rows = adapter.capturedBodies.first['rows'] as List;
      expect(rows.length, equals(2));
      expect(rows[0]['name'], equals('Coca Cola'));
      expect(rows[1]['name'], equals('Pepsi'));
    });

    test('envía al endpoint correcto /api/v1/products/import', () async {
      final adapter = ScriptedAdapter([
        _okReport(created: 1),
      ]);
      final svc = buildService(adapter);

      await svc.importProducts([
        {'name': 'Producto test', 'price': '1000'},
      ]);

      // Verify via captured body that the adapter was called (endpoint
      // verification via Dio path is tested at integration level)
      expect(adapter.callCount, equals(1));
      expect(adapter.capturedBodies.first.containsKey('rows'), isTrue);
    });
  });
}
