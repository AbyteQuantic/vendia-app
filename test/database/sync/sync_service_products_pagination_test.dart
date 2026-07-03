// Spec: specs/088 (paginación completa del catálogo offline del POS)
//
// Auditoría 2026-07-02 (concilio POS↔Inventario↔Kardex): SyncService's
// periodic pull (`_pullFromServer`, Timer.periodic cada 30s) hacía UNA sola
// llamada a GET /api/v1/products sin `page`/`per_page`. El backend cae a su
// default `per_page=20` (pagination.go) y `DatabaseService.replaceAllProducts`
// REEMPLAZA toda la caché Isar por esos 20 productos — en cualquier tenant
// con más de 20 SKU, cada 30s el catálogo offline del POS quedaba truncado
// a 20 ítems, en móvil real (Constitución Art. II). Este archivo cubre el
// fix: `fetchAllProductPagesForSync` ahora recorre TODAS las páginas hasta
// `total_pages`, igual que ya hacía `cart_controller.dart` (Spec 088).
//
// La escritura a Isar (`_db.replaceAllProducts`) no es testeable sin un
// Isar real inicializado (ver integration_test/isar_persistence_test.dart),
// así que este archivo cubre la parte SÍ testeable sin esa infraestructura:
// que la llamada de red recorra todas las páginas y acumule el resultado.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/database/database_service.dart';
import 'package:vendia_pos/database/sync/connectivity_monitor.dart';
import 'package:vendia_pos/database/sync/sync_service.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Adaptador Dio que responde una lista de productos paginada, [totalItems]
/// repartidos en páginas de 100 (el `perPage` fijo que usa
/// `fetchAllProductPagesForSync`).
class _PaginatedProductsAdapter implements HttpClientAdapter {
  _PaginatedProductsAdapter({required this.totalItems});

  final int totalItems;
  final int perPageExpected = 100;
  final List<int> requestedPages = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page = int.parse(options.queryParameters['page'].toString());
    final perPage = int.parse(options.queryParameters['per_page'].toString());
    expect(perPage, perPageExpected,
        reason: 'debe pedir per_page=$perPageExpected, no el default de 20');
    requestedPages.add(page);

    final totalPages = (totalItems / perPage).ceil().clamp(1, 1 << 30);
    final start = (page - 1) * perPage;
    final end = (start + perPage).clamp(0, totalItems);
    final items = List.generate(
      (end - start).clamp(0, totalItems),
      (i) => {
        'id': 'p-${start + i}',
        'name': 'Producto ${start + i}',
        'price': 1000,
        'stock': 5,
      },
    );

    return ResponseBody.fromString(
      jsonEncode({
        'data': items,
        'total': totalItems,
        'page': page,
        'per_page': perPage,
        'total_pages': totalPages,
      }),
      200,
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

  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    // getToken() lee de flutter_secure_storage — sin este mock devuelve
    // null y fetchAllProductPagesForSync corta antes de llegar a la red.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (call) async =>
          call.method == 'read' ? 'fake-jwt-token' : <String, String>{},
    );
    // buildSync() construye un ConnectivityMonitor real (mismo patrón que
    // test/screens/customer_form_test.dart) — sin este mock su _init()
    // lanza MissingPluginException al chequear conectividad.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      connectivityChannel,
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  SyncService buildSync() => SyncService(
        db: DatabaseService.instance,
        connectivity: ConnectivityMonitor(),
        auth: AuthService(),
      );

  test(
      'recorre TODAS las páginas (no solo la primera de 100) y acumula el '
      'catálogo completo — regresión del bug que truncaba la caché Isar a '
      '20 productos cada 30s', () async {
    // 250 productos → 3 páginas de 100 (100+100+50), NO 1 sola página.
    final adapter = _PaginatedProductsAdapter(totalItems: 250);
    final sync = buildSync();
    sync.httpClientAdapterForTesting = adapter;

    final products = await sync.fetchAllProductPagesForSync();

    expect(products, isNotNull);
    expect(products!.length, 250,
        reason: 'debe traer las 250 referencias, no truncar a 20 ni a 100');
    expect(adapter.requestedPages, [1, 2, 3],
        reason: 'debe pedir cada página hasta agotar total_pages');
  });

  test('un catálogo pequeño (<=100) hace una sola llamada, sin páginas de más',
      () async {
    final adapter = _PaginatedProductsAdapter(totalItems: 15);
    final sync = buildSync();
    sync.httpClientAdapterForTesting = adapter;

    final products = await sync.fetchAllProductPagesForSync();

    expect(products!.length, 15);
    expect(adapter.requestedPages, [1]);
  });

  test('cada página se pide con per_page=100, nunca el default de 20 del '
      'backend', () async {
    final adapter = _PaginatedProductsAdapter(totalItems: 5);
    final sync = buildSync();
    sync.httpClientAdapterForTesting = adapter;

    await sync.fetchAllProductPagesForSync();
    // La aserción per_page=100 vive dentro del adapter (perPageExpected);
    // si el código regresara al bug (sin page/per_page) esta prueba
    // fallaría con "type 'Null' is not a subtype of type 'String'" al
    // intentar parsear queryParameters['page'].
  });

  test('respeta el scope de sucursal activa (ApiService.currentBranchId)',
      () async {
    ApiService.currentBranchId = 'sede-norte-uuid';
    addTearDown(() => ApiService.currentBranchId = null);

    String? capturedBranch;
    final sync = buildSync();
    sync.httpClientAdapterForTesting = _CapturingAdapter((opts) {
      capturedBranch = opts.queryParameters['branch_id'] as String?;
    });

    await sync.fetchAllProductPagesForSync();

    expect(capturedBranch, 'sede-norte-uuid');
  });
}

/// Adaptador mínimo que solo inspecciona la request y devuelve una página
/// vacía — usado cuando el test solo necesita verificar query params.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.onRequest);
  final void Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest(options);
    return ResponseBody.fromString(
      jsonEncode({'data': [], 'total': 0, 'page': 1, 'per_page': 100, 'total_pages': 1}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
