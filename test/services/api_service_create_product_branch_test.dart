// Spec: specs/014-inventario-solido-scope-sede/spec.md
//
// Regression guard for FR-01 / FR-04 — the frontend side of the
// "inventario sólido" fix.
//
// Root cause (Spec 014 §2): products were created with branch_id NULL
// because `ApiService.createProduct` shipped the payload as-is, without
// the active sede — unlike `createSale`, which already injects
// `currentBranchId`. A NULL sede makes the product invisible to the
// scoped reads used by Inventario and Dashboard.
//
// The fix (D1): `createProduct` now injects `ApiService.currentBranchId`
// into the payload when it is set and the caller didn't already provide
// a `branch_id` — defense in depth alongside the backend default-sede
// resolution.
//
// The HTTP layer is mocked with a scripted Dio adapter, so the test
// asserts the exact JSON body sent to `POST /api/v1/products` without
// touching the network.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// A Dio adapter that captures the request body and replies with a
/// fixed 201 envelope, modelling the backend's create-product response.
class _CapturingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastBody;
  Map<String, dynamic>? lastQueryParams;
  String? lastPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastQueryParams = Map<String, dynamic>.from(options.queryParameters);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = chunks.expand((c) => c).toList();
      final raw = utf8.decode(bytes);
      lastBody = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    }
    final responsePayload = jsonEncode({
      'data': {'id': lastBody?['id'], 'name': lastBody?['name']},
    });
    return ResponseBody.fromString(
      responsePayload,
      201,
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

  late ApiService api;
  late _CapturingAdapter adapter;

  setUpAll(() {
    // ApiConfig.baseUrl reads dotenv; load a stub so ApiService can be
    // constructed in a flutter_test (no real .env on the test runner).
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');

    // AuthService backs getToken() with flutter_secure_storage, a
    // MethodChannel plugin with no implementation on the test runner.
    // Stub it so the JWT interceptor resolves to "no token" instead of
    // throwing MissingPluginException.
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

  setUp(() {
    ApiService.currentBranchId = null;
    api = ApiService(AuthService());
    adapter = _CapturingAdapter();
    api.httpClientAdapterForTesting = adapter;
  });

  tearDown(() {
    ApiService.currentBranchId = null;
  });

  group('ApiService.createProduct — sede injection (Spec 014, FR-01)', () {
    test(
        'injects the active currentBranchId into the payload '
        'so the product is never created with branch_id NULL', () async {
      ApiService.currentBranchId =
          '11111111-1111-1111-1111-111111111111';

      await api.createProduct({
        'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'name': 'Llaveros',
        'price': 5000,
        'stock': 10,
      });

      expect(adapter.lastPath, '/api/v1/products');
      expect(adapter.lastBody?['branch_id'],
          '11111111-1111-1111-1111-111111111111',
          reason: 'createProduct must attach the sede like createSale does');
    });

    test(
        'does NOT overwrite a branch_id the caller already set '
        '(explicit payload keeps priority)', () async {
      ApiService.currentBranchId =
          '11111111-1111-1111-1111-111111111111';

      await api.createProduct({
        'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'name': 'Producto sede explícita',
        'price': 3000,
        'branch_id': '99999999-9999-9999-9999-999999999999',
      });

      expect(adapter.lastBody?['branch_id'],
          '99999999-9999-9999-9999-999999999999',
          reason: 'an explicit branch_id must not be clobbered');
    });

    test(
        'omits branch_id when no sede is active '
        '(mono-sede / context not loaded — backend resolves the default)',
        () async {
      ApiService.currentBranchId = null;

      await api.createProduct({
        'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'name': 'Producto sin contexto de sede',
        'price': 2000,
      });

      expect(adapter.lastBody?.containsKey('branch_id'), isFalse,
          reason: 'no client sede → the backend assigns the default sede');
    });

    test('overwrites an empty-string branch_id with the active sede',
        () async {
      ApiService.currentBranchId =
          '22222222-2222-2222-2222-222222222222';

      await api.createProduct({
        'id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'name': 'Producto branch vacío',
        'price': 1000,
        'branch_id': '',
      });

      expect(adapter.lastBody?['branch_id'],
          '22222222-2222-2222-2222-222222222222',
          reason: 'an empty string is not a valid sede — treat it as unset');
    });
  });

  group('ApiService.fetchProducts — shared sede scope (Spec 014, FR-04)', () {
    // FR-04: POS, Inventario and Dashboard must show the SAME set of
    // products. Inventario and Dashboard read via fetchProducts; the
    // POS reads from Isar, populated by SyncService._pullFromServer.
    // After the Spec 014 fix the sync pull attaches `branch_id` from
    // ApiService.currentBranchId exactly like fetchProducts does — so
    // pinning fetchProducts' query-param contract pins the scope all
    // three screens now share.

    test('attaches branch_id from currentBranchId as a query param',
        () async {
      ApiService.currentBranchId =
          '33333333-3333-3333-3333-333333333333';

      await api.fetchProducts();

      expect(adapter.lastQueryParams?['branch_id'],
          '33333333-3333-3333-3333-333333333333',
          reason: 'the scoped read used by Inventario/Dashboard — and now '
              'by the POS sync — must carry the active sede');
    });

    test('omits branch_id when no sede is active (legacy tenant-wide read)',
        () async {
      ApiService.currentBranchId = null;

      await api.fetchProducts();

      expect(adapter.lastQueryParams?.containsKey('branch_id'), isFalse,
          reason: 'no sede context → tenant-wide response, no regression');
    });
  });
}
