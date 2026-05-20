// Spec: specs/026-importador-clientes/spec.md
//
// Tests for ApiService.importCustomers:
//   - Sends rows in chunks of 100 (AC-06 / T-13)
//   - Retries up to 3 times on network/5xx errors (AC-07 / FR-11)
//   - Does NOT retry on 4xx errors
//   - Aggregates reports from all chunks into one ImportReport
//
// Uses a scripted Dio HttpClientAdapter — no real network.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

// ── Scripted adapter (same pattern as cold_start_retry_interceptor_test.dart) ─

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<ResponseBody Function(RequestOptions, List<int>?)> script;
  int callCount = 0;
  final List<Map<String, dynamic>> capturedBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Capture the body bytes for assertion
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      try {
        capturedBodies.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
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

/// Returns a 200 response with the given import report payload.
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

/// Returns a DioException of the given type.
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

// ── Stub AuthService ──────────────────────────────────────────────────────────

class _StubAuth extends AuthService {
  @override
  Future<String?> getToken() async => 'test-token-123';
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Builds an ApiService wired to the scripted adapter.
/// [retryDelays] is injected so retries are instant in tests.
/// ColdStartRetryInterceptor is disabled so it does not add its own
/// delays (5 s, 12 s, 25 s) on top of the import-retry logic.
ApiService buildService(
  _ScriptedAdapter adapter, {
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

/// Generates [n] import rows.
List<Map<String, dynamic>> _rows(int n) => List.generate(
      n,
      (i) => {'name': 'Cliente $i', 'phone': '300000${i.toString().padLeft(4, '0')}'},
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test');
  });

  group('ApiService.importCustomers — chunking (AC-06)', () {
    test('250 rows → 3 requests of 100, 100, 50', () async {
      final adapter = _ScriptedAdapter([
        _okReport(created: 100),
        _okReport(created: 100),
        _okReport(created: 50),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(250));

      expect(adapter.callCount, equals(3));
      expect(report.created, equals(250));
      expect(report.updated, equals(0));
    });

    test('100 rows → 1 request', () async {
      final adapter = _ScriptedAdapter([
        _okReport(created: 100),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(100));

      expect(adapter.callCount, equals(1));
      expect(report.created, equals(100));
    });

    test('0 rows → 0 requests, empty report', () async {
      final adapter = _ScriptedAdapter([]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers([]);

      expect(adapter.callCount, equals(0));
      expect(report.created, equals(0));
    });

    test('101 rows → 2 requests (100 + 1)', () async {
      final adapter = _ScriptedAdapter([
        _okReport(created: 100),
        _okReport(created: 1),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(101));

      expect(adapter.callCount, equals(2));
      expect(report.created, equals(101));
    });

    test('aggregates created+updated+skipped+failed across chunks', () async {
      final adapter = _ScriptedAdapter([
        _okReport(created: 90, updated: 5, skipped: 3, failed: [
          {'row_index': 2, 'reason': 'nombre vacío'},
        ]),
        _okReport(created: 80, updated: 10, skipped: 0, failed: [
          {'row_index': 0, 'reason': 'nombre muy corto'},
          {'row_index': 3, 'reason': 'nombre vacío'},
        ]),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(200));

      expect(report.created, equals(170));
      expect(report.updated, equals(15));
      expect(report.skipped, equals(3));
      expect(report.failed.length, equals(3));
    });
  });

  group('ApiService.importCustomers — retry on network/5xx (AC-07, FR-11)', () {
    test('connection error on first attempt → retries → succeeds', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _okReport(created: 5),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(5));

      // 1 fail + 1 success = 2 adapter hits for 1 logical chunk
      expect(adapter.callCount, equals(2));
      expect(report.created, equals(5));
    });

    test('5xx error on first attempt → retries → succeeds', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 500),
        _okReport(created: 3),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(3));

      expect(adapter.callCount, equals(2));
      expect(report.created, equals(3));
    });

    test('503 on first two attempts → succeeds on third', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 503),
        _fail(DioExceptionType.badResponse, status: 503),
        _okReport(created: 2),
      ]);
      final svc = buildService(adapter);

      final report = await svc.importCustomers(_rows(2));

      expect(adapter.callCount, equals(3));
      expect(report.created, equals(2));
    });

    test('fails 3 times → propagates error (max retries exceeded)', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError), // 4th = beyond limit
      ]);
      final svc = buildService(adapter);

      await expectLater(
        svc.importCustomers(_rows(5)),
        throwsA(isA<Exception>()),
      );
      // Should have been called 1 (original) + 3 retries = 4 times max
      expect(adapter.callCount, lessThanOrEqualTo(4));
    });

    test('4xx error (400) is NOT retried', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 400),
      ]);
      final svc = buildService(adapter);

      await expectLater(
        svc.importCustomers(_rows(5)),
        throwsA(isA<Exception>()),
      );
      // Exactly 1 call — no retry on 4xx
      expect(adapter.callCount, equals(1));
    });

    test('4xx error (422) is NOT retried', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 422),
      ]);
      final svc = buildService(adapter);

      await expectLater(
        svc.importCustomers(_rows(5)),
        throwsA(isA<Exception>()),
      );
      // Exactly 1 call — no retry on 4xx
      expect(adapter.callCount, equals(1));
    });
  });

  group('ApiService.importCustomers — request payload', () {
    test('includes dedup_strategy=merge_by_phone', () async {
      final adapter = _ScriptedAdapter([
        _okReport(created: 1),
      ]);
      final svc = buildService(adapter);

      await svc.importCustomers([
        {'name': 'Pedro', 'phone': '3001234567'},
      ]);

      expect(adapter.capturedBodies.first['dedup_strategy'],
          equals('merge_by_phone'));
    });

    test('rows are sent correctly in the payload', () async {
      final adapter = _ScriptedAdapter([
        _okReport(created: 2),
      ]);
      final svc = buildService(adapter);

      await svc.importCustomers([
        {'name': 'Juan', 'phone': '3001111111'},
        {'name': 'Ana', 'phone': '3002222222'},
      ]);

      final rows = adapter.capturedBodies.first['rows'] as List;
      expect(rows.length, equals(2));
      expect(rows[0]['name'], equals('Juan'));
      expect(rows[1]['name'], equals('Ana'));
    });
  });
}
