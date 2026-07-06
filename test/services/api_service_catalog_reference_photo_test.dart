// Spec: specs/096-foto-referencia-verificada/spec.md
//
// fetchCatalogReferencePhoto: 200 devuelve el mapa de datos; 404 (sin
// match) devuelve null SIN lanzar excepción — la sugerencia debe caer en
// silencio al flujo actual (AC-04), nunca mostrar un error al tendero.
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FixedStatusAdapter implements HttpClientAdapter {
  final int statusCode;
  final String payload;
  _FixedStatusAdapter(this.statusCode, this.payload);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(payload, statusCode,
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

  test('200 con match devuelve el mapa de datos', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting = _FixedStatusAdapter(200, '''
      {"data":{"catalog_product_id":"cp1","image_url":"https://off.example/x.jpg","brand":"Coca-Cola","name":"Coca-Cola 400ml"}}
    ''');

    final result = await api.fetchCatalogReferencePhoto('7702090000012');
    expect(result, isNotNull);
    expect(result!['image_url'], 'https://off.example/x.jpg');
    expect(result['name'], 'Coca-Cola 400ml');
  });

  test('404 sin match devuelve null SIN lanzar excepción', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting =
        _FixedStatusAdapter(404, '{"error":"sin foto de referencia"}');

    final result = await api.fetchCatalogReferencePhoto('0000000000000');
    expect(result, isNull);
  });

  test('error de red (500) devuelve null SIN lanzar excepción', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting =
        _FixedStatusAdapter(500, '{"error":"boom"}');

    final result = await api.fetchCatalogReferencePhoto('7702090000012');
    expect(result, isNull);
  });
}
