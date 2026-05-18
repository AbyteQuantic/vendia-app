// Spec: specs/012-cold-start-resiliencia/spec.md
//
// FR-03 / AC-03 — at app startup we fire a single `GET /ping` against
// the backend root so a sleeping Render instance starts waking up
// BEFORE the merchant performs their first real action. The ping is
// fire-and-forget: it must never `await`-block the UI and never throw
// into the startup path. If the backend is asleep this request itself
// takes ~50 s — that is fine, nothing waits on it.
//
// `/ping` is a public, unauthenticated root route (verified in spec
// §2: 200 in ~0.2 s when warm), so this needs no JWT and is kept off
// the main authenticated `ApiService` Dio client on purpose.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';

/// Triggers a non-blocking warm-up ping to the backend.
class BackendWarmup {
  BackendWarmup._();

  /// Fire-and-forget `GET /ping`. Returns immediately; the actual
  /// request runs in the background. Errors are logged, never thrown —
  /// a failed warm-up simply means the first real call pays the
  /// cold-start cost (and is itself covered by the retry interceptor).
  static void ping() {
    // Intentionally NOT awaited by the caller. The async body below
    // owns the request and its error handling end-to-end.
    unawaited(_doPing());
  }

  static Future<void> _doPing() async {
    // A short connect timeout, but a long receive timeout: a cold
    // Render backend can take ~50 s to answer `/ping`. We still want
    // that full window so the warm-up actually finishes the wake-up.
    final dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 75),
      receiveTimeout: const Duration(seconds: 75),
    ));
    try {
      final response = await dio.get<dynamic>('/ping');
      debugPrint('[WARMUP] backend ping ok (${response.statusCode})');
    } on DioException catch (e) {
      // Expected when the backend is mid-cold-start or offline. The
      // first real API call will retry via ColdStartRetryInterceptor.
      debugPrint('[WARMUP] backend ping failed (${e.type}) — '
          'first call will retry');
    } finally {
      dio.close();
    }
  }
}
