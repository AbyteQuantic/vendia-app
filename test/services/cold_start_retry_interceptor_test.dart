// Spec: specs/012-cold-start-resiliencia/spec.md
//
// Exercises ColdStartRetryInterceptor against a Dio mock HttpClientAdapter
// (no real network). The adapter is scripted so the first N attempts
// raise a cold-start error and a later attempt succeeds — modelling a
// Render backend waking up.
//
// Coverage maps to the spec:
//   FR-01 / AC-01 — connectionError on early attempts, success later →
//                   the call resolves OK, no error reaches the caller.
//   FR-04 / AC-02 — every attempt fails → the caller gets the soft
//                   AppError ("No pudimos conectar...").
//   FR-05         — strict attempt cap: the adapter is hit at most
//                   kColdStartMaxAttempts times.
//   FR-06 / D3    — connectionError is always retried; a POST
//                   receiveTimeout is NOT retried (could duplicate).
//   AC-04         — a non-cold-start error (404) is passed straight
//                   through without retries.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/cold_start_retry_interceptor.dart';

/// A scripted Dio adapter. Each entry in [script] is invoked once, in
/// order, when a request reaches the adapter; the last entry repeats if
/// the interceptor somehow over-fetches (so an over-retry surfaces as a
/// callCount assertion rather than a range error).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<ResponseBody Function(RequestOptions)> script;
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = callCount < script.length ? callCount : script.length - 1;
    callCount++;
    return script[index](options);
  }

  @override
  void close({bool force = false}) {}
}

/// A scripted step that raises a [DioException] of [type] (optionally
/// with [status]) — modelling a failed attempt.
ResponseBody Function(RequestOptions) _fail(
  DioExceptionType type, {
  int? status,
}) {
  return (options) {
    throw DioException(
      requestOptions: options,
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: options,
              statusCode: status,
              data: {'error': 'bad gateway'},
            ),
    );
  };
}

/// A scripted step that returns a 200 — modelling the backend finally
/// awake and answering.
ResponseBody Function(RequestOptions) _ok() {
  return (options) => ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}

void main() {
  /// Builds a Dio wired with the cold-start interceptor and the scripted
  /// adapter. Retry delays are zeroed so tests run instantly.
  Dio buildDio(_ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      ColdStartRetryInterceptor(
        dio: dio,
        retryDelays: const [
          Duration.zero,
          Duration.zero,
          Duration.zero,
        ],
        delay: (_) async {},
      ),
    );
    return dio;
  }

  group('ColdStartRetryInterceptor — transparent retry (FR-01, AC-01)', () {
    test(
        'connectionError on the first two attempts then success → '
        'the request resolves without surfacing an error', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _ok(),
      ]);
      final dio = buildDio(adapter);

      final response = await dio.get<dynamic>('/api/v1/sales/today');

      expect(response.statusCode, 200);
      // Original call + 2 retries = 3 hits on the adapter.
      expect(adapter.callCount, 3);
    });

    test('connectionTimeout then success on the very next attempt', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.connectionTimeout),
        _ok(),
      ]);
      final dio = buildDio(adapter);

      final response = await dio.get<dynamic>('/api/v1/products');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('a transient 503 on a GET is retried then succeeds', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 503),
        _ok(),
      ]);
      final dio = buildDio(adapter);

      final response = await dio.get<dynamic>('/api/v1/inventory/alerts');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });
  });

  group('ColdStartRetryInterceptor — exhaustion (FR-04, FR-05, AC-02)', () {
    test(
        'every attempt fails → the error reaches the caller and the soft '
        'AppError copy is produced; the adapter is hit exactly '
        'kColdStartMaxAttempts times', () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
        _fail(DioExceptionType.connectionError),
      ]);
      final dio = buildDio(adapter);

      DioException? thrown;
      try {
        await dio.get<dynamic>('/api/v1/sales/today');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull, reason: 'all retries failed → must throw');
      // Strict cap: 1 original + 3 retries, never more.
      expect(adapter.callCount, kColdStartMaxAttempts);

      // The exhausted error maps to the soft, non-alarming copy (FR-04).
      final appError = AppError.fromDioException(thrown!);
      expect(appError.type, AppErrorType.network);
      expect(appError.message, contains('No pudimos conectar'));
    });
  });

  group('ColdStartRetryInterceptor — what is NOT retried (FR-06, AC-04)', () {
    test('a POST that hits receiveTimeout is NOT retried (could duplicate)',
        () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.receiveTimeout),
        _ok(), // would be used if it (wrongly) retried
      ]);
      final dio = buildDio(adapter);

      DioException? thrown;
      try {
        await dio.post<dynamic>('/api/v1/sales', data: {'total': 1000});
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      // No retry: the adapter saw the POST exactly once.
      expect(adapter.callCount, 1);
    });

    test('a POST that hits connectionError IS retried (no socket = safe)',
        () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.connectionError),
        _ok(),
      ]);
      final dio = buildDio(adapter);

      final response =
          await dio.post<dynamic>('/api/v1/sales', data: {'total': 1000});

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('a 404 is passed straight through without any retry (AC-04)',
        () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 404),
        _ok(),
      ]);
      final dio = buildDio(adapter);

      DioException? thrown;
      try {
        await dio.get<dynamic>('/api/v1/products/missing');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.response?.statusCode, 404);
      // 404 is not a cold start → no retry.
      expect(adapter.callCount, 1);
    });

    test('a 503 on a POST is NOT retried (write verb, could duplicate)',
        () async {
      final adapter = _ScriptedAdapter([
        _fail(DioExceptionType.badResponse, status: 503),
        _ok(),
      ]);
      final dio = buildDio(adapter);

      DioException? thrown;
      try {
        await dio.post<dynamic>('/api/v1/sales', data: {'total': 1000});
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(adapter.callCount, 1);
    });
  });
}
