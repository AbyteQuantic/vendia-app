// Spec: specs/101-retocar-fotos-inventario/spec.md (fix 401 chip retoque)
//
// BUG (prod, tenant e6d3effd "Ropa Test QA"): el flujo de REGISTRO
// (onboarding_stepper) persistía `vendia_tenant_id` VACÍO — la respuesta de
// /tenant/register es workspace-shape (AuthResponse: `tenant_id` top-level)
// pero el callback la parseaba como si trajera un mapa anidado
// `data['tenant']`, que no existe. Con tenant_id vacío,
// ManageInventoryScreen._loadTenantId() aborta y el chip "Fotos sin
// retocar" + GET /inventory/retouch/summary nunca se disparan (y cuando la
// request se emitió sin sesión completa, salía SIN Authorization → 401).
//
// Esta capa del fix: `getTenantId()` se AUTO-REPARA — si el valor guardado
// está vacío pero hay un JWT válido, recupera el claim `tenant_id` del
// token, lo re-persiste y lo devuelve. Cubre las sesiones YA rotas en
// producción sin obligar a cerrar sesión.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/auth_service.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Mock in-memory de secure storage (mismo patrón que
/// auth_service_sequential_write_test.dart).
class _SecureStorageMock {
  final Map<String, String?> store = {};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
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
        .setMockMethodCallHandler(_secureStorageChannel, null);
  }
}

/// JWT falso (sin firma real) con los claims dados — getTenantId solo
/// decodifica el payload, no valida la firma (eso lo hace el backend).
String _fakeJwt(Map<String, dynamic> claims) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64(claims)}.firma-falsa';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SecureStorageMock storage;
  late AuthService auth;

  setUp(() {
    storage = _SecureStorageMock()..install();
    auth = AuthService();
  });

  tearDown(() => storage.uninstall());

  group('getTenantId — auto-reparación desde el claim del JWT', () {
    test('tenant_id vacío + JWT con claim → devuelve el claim', () async {
      storage.store['vendia_tenant_id'] = '';
      storage.store['vendia_jwt'] =
          _fakeJwt({'tenant_id': 'e6d3effd-b870-47b1-8c88-ccc046615d7b'});

      expect(await auth.getTenantId(),
          'e6d3effd-b870-47b1-8c88-ccc046615d7b');
    });

    test('re-persiste el claim recuperado (siguiente lectura sin JWT)',
        () async {
      storage.store['vendia_tenant_id'] = '';
      storage.store['vendia_jwt'] = _fakeJwt({'tenant_id': 'tenant-sano'});

      await auth.getTenantId();

      expect(storage.store['vendia_tenant_id'], 'tenant-sano',
          reason: 'el self-heal debe dejar el storage reparado');
    });

    test('tenant_id ausente (clave no escrita) también se repara', () async {
      storage.store['vendia_jwt'] = _fakeJwt({'tenant_id': 'tenant-abc'});

      expect(await auth.getTenantId(), 'tenant-abc');
    });

    test('un tenant_id guardado válido MANDA (no se toca el storage)',
        () async {
      storage.store['vendia_tenant_id'] = 'tenant-guardado';
      storage.store['vendia_jwt'] = _fakeJwt({'tenant_id': 'otro-tenant'});

      expect(await auth.getTenantId(), 'tenant-guardado');
    });

    test('sin JWT no hay nada que reparar: devuelve lo guardado', () async {
      storage.store['vendia_tenant_id'] = '';

      expect((await auth.getTenantId()) ?? '', isEmpty);
    });

    test('JWT malformado no revienta: devuelve lo guardado', () async {
      storage.store['vendia_tenant_id'] = '';
      storage.store['vendia_jwt'] = 'esto-no-es-un-jwt';

      expect((await auth.getTenantId()) ?? '', isEmpty);
    });

    test('JWT sin claim tenant_id (token temporal) no repara con basura',
        () async {
      storage.store['vendia_tenant_id'] = '';
      storage.store['vendia_jwt'] = _fakeJwt({'user_id': 'u-1'});

      expect((await auth.getTenantId()) ?? '', isEmpty);
    });
  });
}
