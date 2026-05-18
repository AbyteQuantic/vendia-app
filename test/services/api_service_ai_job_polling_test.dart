// Spec: specs/016-ia-foto-async-polling/spec.md
//
// Regression guard for FR-03 / FR-04 / FR-05 — the frontend side of the
// async AI photo feature.
//
// Background (Spec 016 §3): improving / generating a product photo with
// Gemini is slow and variable (~20–90s). The old synchronous model
// blocked one long request; if it overran the timeout the tendero saw a
// network error — pure friction (F015 only widened the window).
//
// The new contract:
//  - POST /products/{id}/enhance|generate-image → 202
//    {data:{job_id, status:"processing"}}
//  - GET  /products/{id}/ai-job/{jobId} → {data:{status, photo_url?, error?}}
//
// `ApiService.enhanceProductPhoto` / `generateProductImage` now encapsulate
// the POST + the poll loop, so screens keep their plain `await` + loader.
// This suite drives that loop with a scripted Dio adapter (no network):
//  - POST → job_id, then GET processing → done returns the result map;
//  - GET → failed throws an AppError carrying the backend's Spanish reason;
//  - the poll budget being exhausted throws a clear Spanish AppError —
//    never a raw timeout.
//
// The poll interval / total budget are shrunk via setAiPollTimingForTesting
// so the loop runs in milliseconds, not minutes.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// A Dio adapter that replies with a scripted sequence of responses.
///
/// The POST that starts the job always answers 202 with [jobId]. Each
/// subsequent GET to the status endpoint pops the next entry from
/// [pollResponses]; the last entry repeats if the loop polls more times
/// than scripted (useful for the timeout case, where every poll stays
/// `processing`).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({
    required this.jobId,
    required this.pollResponses,
  });

  final String jobId;
  final List<Map<String, dynamic>> pollResponses;

  int postCount = 0;
  int getCount = 0;
  final List<String> requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);

    if (options.method == 'POST') {
      postCount++;
      return _json(202, {
        'data': {'job_id': jobId, 'status': 'processing'},
      });
    }

    // GET status poll.
    final index =
        getCount < pollResponses.length ? getCount : pollResponses.length - 1;
    getCount++;
    return _json(200, {'data': pollResponses[index]});
  }

  ResponseBody _json(int status, Map<String, dynamic> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const productId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const jobId = 'job-7f3c1e9a';

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

  ApiService buildApi(_ScriptedAdapter adapter) {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = adapter;
    // Drive the poll loop in milliseconds — a real 4s interval / 3 min
    // budget would make this suite unbearably slow.
    api.setAiPollTimingForTesting(
      interval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 60),
    );
    return api;
  }

  group('ApiService.enhanceProductPhoto — POST 202 + polling (Spec 016)', () {
    test(
        'POSTs to /enhance, polls the ai-job endpoint while processing, '
        'and returns the result map once the job is done (FR-03/AC-03)',
        () async {
      final adapter = _ScriptedAdapter(
        jobId: jobId,
        pollResponses: [
          {'status': 'processing'},
          {'status': 'processing'},
          {
            'status': 'done',
            'photo_url': 'https://cdn.vendia.store/products/$productId.png',
          },
        ],
      );
      final api = buildApi(adapter);

      final result = await api.enhanceProductPhoto(productId, name: 'Arroz');

      expect(adapter.postCount, 1,
          reason: 'the job is started with exactly one POST');
      expect(adapter.getCount, 3,
          reason: 'the loop polls until the status is done');
      expect(result['status'], 'done');
      expect(result['photo_url'],
          'https://cdn.vendia.store/products/$productId.png',
          reason: 'a done job returns its photo_url like the old sync call');
      expect(adapter.requestedPaths.first,
          '/api/v1/products/$productId/enhance');
      expect(adapter.requestedPaths[1],
          '/api/v1/products/$productId/ai-job/$jobId');
    });

    test(
        'throws an AppError carrying the backend Spanish reason when the '
        'job reports failed (FR-04/AC-04)', () async {
      final adapter = _ScriptedAdapter(
        jobId: jobId,
        pollResponses: [
          {'status': 'processing'},
          {
            'status': 'failed',
            'error': 'No pudimos mejorar la foto. La imagen no es clara.',
          },
        ],
      );
      final api = buildApi(adapter);

      await expectLater(
        api.enhanceProductPhoto(productId),
        throwsA(
          isA<AppError>().having((e) => e.message, 'message',
              'No pudimos mejorar la foto. La imagen no es clara.'),
        ),
      );
    });

    test(
        'throws a clear Spanish AppError — not a raw timeout — when the '
        'poll budget is exhausted while the job is still processing '
        '(FR-05/AC-04)', () async {
      // Every poll stays processing; the last entry repeats, so the loop
      // only ends when the ~budget runs out.
      final adapter = _ScriptedAdapter(
        jobId: jobId,
        pollResponses: [
          {'status': 'processing'},
        ],
      );
      final api = buildApi(adapter);

      await expectLater(
        api.enhanceProductPhoto(productId),
        throwsA(
          isA<AppError>()
              .having((e) => e.message, 'message',
                  contains('tardando más de lo normal'))
              .having((e) => e.message, 'no raw type leaked',
                  isNot(contains('AppError'))),
        ),
      );
    });
  });

  group('ApiService.generateProductImage — POST 202 + polling (Spec 016)',
      () {
    test(
        'POSTs to /generate-image and returns the result on a done job '
        '(AC-05)', () async {
      final adapter = _ScriptedAdapter(
        jobId: jobId,
        pollResponses: [
          {'status': 'processing'},
          {
            'status': 'done',
            'photo_url': 'https://cdn.vendia.store/generated/$productId.png',
          },
        ],
      );
      final api = buildApi(adapter);

      final result = await api.generateProductImage(productId, name: 'Café');

      expect(adapter.requestedPaths.first,
          '/api/v1/products/$productId/generate-image');
      expect(result['photo_url'],
          'https://cdn.vendia.store/generated/$productId.png');
    });

    test('a failed generate job surfaces its Spanish reason (AC-04/AC-05)',
        () async {
      final adapter = _ScriptedAdapter(
        jobId: jobId,
        pollResponses: [
          {
            'status': 'failed',
            'error': 'No pudimos generar la imagen. Intenta de nuevo.',
          },
        ],
      );
      final api = buildApi(adapter);

      await expectLater(
        api.generateProductImage(productId),
        throwsA(
          isA<AppError>().having((e) => e.message, 'message',
              'No pudimos generar la imagen. Intenta de nuevo.'),
        ),
      );
    });
  });
}
