// Spec: specs/069-catalogo-unificado-eventos-inventario/spec.md
//
// Regression guard: fetchProductCategories parsea la respuesta REAL del
// endpoint, donde `data` es una LISTA (["Bebidas",…]). Antes usaba
// _extractData (que castea `data` a Map) → lanzaba TypeError → el autocomplete
// de categorías quedaba SIEMPRE vacío (bug reportado 2026-06-20).
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _ListAdapter implements HttpClientAdapter {
  final String payload;
  _ListAdapter(this.payload);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(payload, 200,
        headers: {
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
    // getToken() usa flutter_secure_storage (MethodChannel sin impl en test):
    // se stubea para que el interceptor JWT resuelva "sin token" y no cuelgue.
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

  test('fetchProductCategories parsea data como LISTA (no lanza)', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting =
        _ListAdapter('{"data":["Bebidas","Almuerzos","Gaseosas"]}');

    final cats = await api.fetchProductCategories();
    expect(cats, ['Bebidas', 'Almuerzos', 'Gaseosas']);
  });

  test('respuesta vacía → lista vacía, sin excepción', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = _ListAdapter('{"data":[]}');
    expect(await api.fetchProductCategories(), isEmpty);
  });
}
