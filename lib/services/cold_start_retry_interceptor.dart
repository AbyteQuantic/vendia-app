// Spec: specs/012-cold-start-resiliencia/spec.md
//
// Render's free tier sleeps the backend after ~15 min idle; the first
// request after that triggers a cold start of ~50 s. During that window
// Dio raises `connectionError` / `connectionTimeout` (no socket) and the
// merchant sees an alarming "no se pudo contactar el servidor" toast even
// though the backend is merely waking up.
//
// This interceptor makes a cold start look like "cargando", not a
// failure: it transparently re-issues the request a few times with
// backoff, so the loader the screens already show simply stays up until
// the backend answers (FR-01, FR-02, AC-01).
//
// It is intentionally a SEPARATE interceptor placed AFTER the existing
// auth/paywall `InterceptorsWrapper`. Dio runs error interceptors in
// registration order, so the auth interceptor still gets first crack at
// every error: a 401 is consumed (refresh) or re-thrown by it, and the
// soft-paywall 403 is handled there too. By the time an error reaches
// this interceptor it is either a genuine cold-start / transient failure
// or something the auth layer chose to pass through — and we only act on
// the cold-start shape (see [_isRetriable]).

import 'dart:async';

import 'package:dio/dio.dart';

/// Backoff schedule for the retry interceptor.
///
/// D2 — four attempts total: the original request plus three retries.
/// The waits BEFORE each retry are 5 s, 12 s, 25 s → a ~42 s retry
/// window on top of the per-attempt connect/receive timeouts, which
/// comfortably covers a Render cold start (~50 s observed). The first
/// attempt has no wait (index 0 is the original call).
const List<Duration> kColdStartBackoff = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 12),
  Duration(seconds: 25),
];

/// Total number of attempts = 1 original + [kColdStartBackoff.length]
/// retries. Exposed so tests can pin the strict attempt cap (FR-05).
const int kColdStartMaxAttempts = 1 + 3;

/// Header used to carry the current attempt count across retries on the
/// same [RequestOptions]. Kept on the request (not interceptor state) so
/// concurrent requests each track their own attempts independently.
const String kColdStartAttemptHeader = 'x-vendia-cold-start-attempt';

/// Interceptor that retries transient connectivity failures so a Render
/// cold start is absorbed transparently behind the existing loader.
///
/// [retryDelays] is injectable so tests can run with zero waits instead
/// of the production ~42 s schedule. [delay] is injectable for the same
/// reason — the default sleeps for real; tests pass a no-op.
class ColdStartRetryInterceptor extends Interceptor {
  ColdStartRetryInterceptor({
    required Dio dio,
    List<Duration> retryDelays = kColdStartBackoff,
    Future<void> Function(Duration)? delay,
  })  : _dio = dio,
        _retryDelays = retryDelays,
        _delay = delay ?? _sleep;

  /// The same Dio instance the request was issued on. Used to re-fetch
  /// the request; reusing it means the retried request still flows
  /// through the auth interceptor (JWT injection, refresh) untouched.
  final Dio _dio;

  /// Waits before retries 1..N. Length also bounds the retry count.
  final List<Duration> _retryDelays;

  final Future<void> Function(Duration) _delay;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = _attemptOf(err.requestOptions);

    // Strict cap (FR-05): once attempts are exhausted, let the error
    // through so `AppError.fromDioException` can surface the soft
    // final message. The UI is never left hanging.
    if (attempt >= kColdStartMaxAttempts || attempt > _retryDelays.length) {
      handler.next(err);
      return;
    }

    if (!_isRetriable(err)) {
      handler.next(err);
      return;
    }

    // Wait, then re-issue. `_retryDelays[attempt - 1]` because the
    // first retry (attempt == 1) waits `_retryDelays[0]`.
    final wait = _retryDelays[attempt - 1];
    await _delay(wait);

    final retryOptions = _bumpAttempt(err.requestOptions, attempt);
    try {
      final response = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      // Re-enter the interceptor chain so the NEXT failure gets its own
      // retry decision (or hits the cap and is surfaced). We forward
      // the retry's error, not the original, so the final AppError
      // reflects the last real attempt.
      handler.next(retryError);
    }
  }

  /// Current attempt number for a request: 1 = first call, 2 = first
  /// retry, etc. Read from the header so it survives across retries.
  int _attemptOf(RequestOptions options) {
    final raw = options.headers[kColdStartAttemptHeader];
    if (raw is int) return raw;
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return 1;
  }

  /// Returns a copy of [options] with the attempt counter incremented.
  /// Dio's `fetch` mutates and reuses the passed options, so we copy to
  /// avoid clobbering the caller's original request object.
  RequestOptions _bumpAttempt(RequestOptions options, int currentAttempt) {
    final headers = Map<String, dynamic>.from(options.headers)
      ..[kColdStartAttemptHeader] = currentAttempt + 1;
    return options.copyWith(headers: headers);
  }

  /// Decides whether [err] is a transient cold-start failure that is
  /// SAFE to retry — see D3.
  ///
  /// Always-safe (no connection was ever established, so the backend
  /// never received the request, no chance of duplication):
  ///   * connectionError
  ///   * connectionTimeout
  ///   * sendTimeout — the request body never finished uploading.
  ///
  /// Conditionally safe — only for idempotent (non-POST) verbs:
  ///   * receiveTimeout — the server MAY have received and processed
  ///     the request; retrying a POST could double-create a sale or a
  ///     payment. We retry receiveTimeout only for GET/HEAD/PUT/DELETE
  ///     (idempotent by HTTP contract) and skip it for POST/PATCH.
  ///   * 502 / 503 / 504 — a transient gateway error during cold start.
  ///     For a GET this is safe; for a POST the request reached the
  ///     edge and may have been forwarded, so we are conservative and
  ///     do NOT retry write verbs on a 5xx.
  ///
  /// Everything else (4xx, other 5xx, cancellations, bad responses) is
  /// passed straight through — a 401 in particular is NOT a cold start
  /// and must never be retried here (the auth interceptor owns it).
  bool _isRetriable(DioException err) {
    final method = err.requestOptions.method.toUpperCase();
    final isIdempotent = method != 'POST' && method != 'PATCH';

    switch (err.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.receiveTimeout:
        // POST may have been received & processed server-side.
        return isIdempotent;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        final isTransient5xx =
            status == 502 || status == 503 || status == 504;
        return isTransient5xx && isIdempotent;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
      // dio 5.10 añadió transformTimeout y podría añadir más valores: no son
      // cold starts de red → no reintentar. default a prueba de futuro para que
      // dart2js no rompa el build web por un switch no exhaustivo.
      default:
        return false;
    }
  }
}
