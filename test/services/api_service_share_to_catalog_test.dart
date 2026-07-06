// Spec: specs/096-foto-referencia-verificada/spec.md (Adenda A)
//
// shareProductPhotoToCatalog: 200 devuelve true; cualquier error (red,
// 404, 500) devuelve false SIN lanzar excepción — compartir es una
// acción de "ayudar a otros", nunca debe bloquear ni mostrar un error
// al tendero si falla.
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

  test('200 devuelve true', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting =
        _FixedStatusAdapter(200, '{"message":"foto compartida"}');

    final result = await api.shareProductPhotoToCatalog('p1');
    expect(result, isTrue);
  });

  test('400 (sin barcode/foto) devuelve false SIN lanzar excepción',
      () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting =
        _FixedStatusAdapter(400, '{"error":"el producto no tiene foto"}');

    final result = await api.shareProductPhotoToCatalog('p1');
    expect(result, isFalse);
  });

  test('error de red (500) devuelve false SIN lanzar excepción', () async {
    final api = ApiService(AuthService());
    api.httpClientAdapterForTesting =
        _FixedStatusAdapter(500, '{"error":"boom"}');

    final result = await api.shareProductPhotoToCatalog('p1');
    expect(result, isFalse);
  });
}
