// Spec: specs/051-login-emite-capacidades/spec.md
//
// Bug CRÍTICO: el PATCH /store/profile responde solo {"message": ...} (sin
// flags). Pasar esa respuesta a saveFeatureFlagsFromProfile dejaba `merged`
// vacío y el código viejo escribía null en `vendia_feature_flags` → BORRABA
// todas las capacidades del cache. Estas pruebas certifican la guarda
// no-destructiva: un source sin info de flags NUNCA debe pisar el cache.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/auth_service.dart';

const _channel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _MapStorage {
  final Map<String, String?> store = {};
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String?;
          return null;
        case 'read':
          return store[args['key']];
        case 'readAll':
          return store;
        case 'containsKey':
          return store.containsKey(args['key']);
        case 'delete':
          store.remove(args['key']);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        default:
          return null;
      }
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MapStorage storage;
  late AuthService auth;

  setUp(() {
    storage = _MapStorage();
    storage.install();
    auth = AuthService();
  });
  tearDown(() => storage.uninstall());

  test('respuesta {message} del PATCH NO borra los flags cacheados', () async {
    // Cache previo con capacidades activas.
    storage.store['vendia_feature_flags'] =
        '{"enable_recipes":true,"enable_marketing_hub":true,"enable_tables":true}';
    storage.store['vendia_credit_label_mode'] = 'credit';

    // Llega la respuesta del PATCH (solo message, sin flags).
    await auth.saveFeatureFlagsFromProfile({'message': 'perfil actualizado'});

    // El cache de flags se PRESERVA (antes quedaba en null → todo apagado).
    expect(storage.store['vendia_feature_flags'],
        '{"enable_recipes":true,"enable_marketing_hub":true,"enable_tables":true}');
    // credit_label_mode tampoco se resetea a 'fiar'.
    expect(storage.store['vendia_credit_label_mode'], 'credit');
  });

  test('GET de perfil completo SÍ actualiza los flags', () async {
    storage.store['vendia_feature_flags'] = '{"enable_recipes":false}';

    await auth.saveFeatureFlagsFromProfile({
      'feature_flags': {'enable_tables': true, 'enable_events': true},
      'enable_recipes': true,
      'enable_quotes': true,
      'enable_promotions': false,
    });

    final raw = storage.store['vendia_feature_flags']!;
    expect(raw.contains('"enable_recipes":true'), isTrue);
    expect(raw.contains('"enable_quotes":true'), isTrue);
    expect(raw.contains('"enable_tables":true'), isTrue);
    expect(raw.contains('"enable_promotions":false'), isTrue);
  });

  test('source totalmente vacío no escribe (preserva) el cache', () async {
    storage.store['vendia_feature_flags'] = '{"enable_recipes":true}';
    await auth.saveFeatureFlagsFromProfile(<String, dynamic>{});
    expect(storage.store['vendia_feature_flags'], '{"enable_recipes":true}');
  });
}
