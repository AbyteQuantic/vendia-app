// Auditoría 2026-07-02 (concilio POS↔Inventario↔Kardex, Spec 088): el
// backend capa `per_page` a 100 por llamada (pagination.go) sin avisar.
// Varios call sites (Mi Inventario y otros) piden una sola página y quedan
// truncados en cualquier tenant con más de 100 SKU en el scope pedido.
// `ApiService.fetchAllProducts` centraliza el loop de paginación completa
// (mismo patrón que cart_controller.dart ya aplicaba solo para el POS,
// Spec 088) para que los demás consumidores no repitan el bug.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _PaginatedAdapter implements HttpClientAdapter {
  _PaginatedAdapter(this.totalItems);
  final int totalItems;
  final List<Map<String, dynamic>> requestedParams = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedParams.add(options.queryParameters);
    final page = int.parse(options.queryParameters['page'].toString());
    const perPage = 100;
    final totalPages = (totalItems / perPage).ceil().clamp(1, 1 << 30);
    final start = (page - 1) * perPage;
    final end = (start + perPage).clamp(0, totalItems);
    final items = List.generate(
      (end - start).clamp(0, totalItems),
      (i) => {'id': 'p-${start + i}', 'name': 'Producto ${start + i}'},
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

  test(
      'fetchAllProducts recorre todas las páginas — 125 refs (el caso real '
      'del tenant b8d6a9b9…) NO se trunca a 100', () async {
    final adapter = _PaginatedAdapter(125);
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = adapter;

    final products = await api.fetchAllProducts(branchId: 'sede-1');

    expect(products.length, 125);
    expect(adapter.requestedParams.map((p) => p['page']), [1, 2]);
    expect(adapter.requestedParams.every((p) => p['branch_id'] == 'sede-1'),
        isTrue);
  });

  test('un catálogo dentro de una sola página hace una sola llamada',
      () async {
    final adapter = _PaginatedAdapter(40);
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = adapter;

    final products = await api.fetchAllProducts();

    expect(products.length, 40);
    expect(adapter.requestedParams.length, 1);
  });

  test('propaga sellableOnly a cada página pedida', () async {
    final adapter = _PaginatedAdapter(150);
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = adapter;

    await api.fetchAllProducts(sellableOnly: true);

    expect(adapter.requestedParams.length, 2);
    expect(
      adapter.requestedParams.every((p) => p['sellable_only'] == 'true'),
      isTrue,
    );
  });
}
