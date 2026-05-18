// Spec: specs/011-web-auth-token/spec.md
//
// F011 — La app web no envía el token de autenticación.
//
// Causa raíz (confirmada en runtime sobre vendia.store): `AuthService`
// persistía la sesión con `Future.wait([...])`, lanzando 8-10 escrituras
// en PARALELO. En web, `flutter_secure_storage_web` tiene un check-then-act
// al generar la clave AES (`localStorage['FlutterSecureStorage']`): varias
// escrituras concurrentes ven «no hay clave», cada una genera la suya y
// sobrescribe la anterior. Los valores cifrados con las claves perdidas
// quedan huérfanos y `getToken()` revienta con `OperationError` — la
// petición autenticada se aborta antes de adjuntar el header `Authorization`.
//
// El arreglo serializa las escrituras. Estos tests certifican que ningún
// método de persistencia de sesión deja dos escrituras en vuelo a la vez.
// Si un futuro refactor reintroduce `Future.wait`, estos tests fallan.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/auth_service.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Mock de secure storage que detecta solapamiento de escrituras.
///
/// Cada `write` marca un flag mientras está «en vuelo» y cede el control
/// (`Future.delayed`) antes de completar — replicando que la escritura web
/// real es asíncrona. Si una segunda escritura entra mientras la primera
/// sigue en vuelo, se registra como concurrencia: exactamente la condición
/// de carrera que rompe `flutter_secure_storage_web`.
class _SecureStorageProbe {
  final Map<String, String?> store = {};
  int writesInFlight = 0;
  int maxConcurrentWrites = 0;
  int totalWrites = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'write':
          totalWrites++;
          writesInFlight++;
          if (writesInFlight > maxConcurrentWrites) {
            maxConcurrentWrites = writesInFlight;
          }
          // Cede el event loop: simula la naturaleza async de la
          // escritura web (crypto.subtle.encrypt + localStorage).
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          store[args['key'] as String] = args['value'] as String?;
          writesInFlight--;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SecureStorageProbe probe;
  late AuthService auth;

  setUp(() {
    probe = _SecureStorageProbe()..install();
    auth = AuthService();
  });

  tearDown(() => probe.uninstall());

  group('F011 — AuthService escribe la sesión de forma secuencial', () {
    test('saveWorkspaceSession no deja dos escrituras en vuelo a la vez',
        () async {
      await auth.saveWorkspaceSession(
        accessToken: 'jwt-abc',
        refreshToken: 'refresh-xyz',
        tenantId: 'tenant-1',
        ownerName: 'Ana',
        businessName: 'Tienda Ana',
        userId: 'user-1',
        branchId: 'branch-1',
        role: 'owner',
        featureFlags: const {'enable_services': true},
        businessTypes: const ['minimercado'],
      );

      expect(probe.totalWrites, greaterThan(1),
          reason: 'el método debe persistir varias claves');
      expect(probe.maxConcurrentWrites, 1,
          reason: 'las escrituras deben ser secuenciales para no disparar la '
              'carrera de clave AES de flutter_secure_storage_web');
    });

    test('saveSession no deja dos escrituras en vuelo a la vez', () async {
      await auth.saveSession(
        accessToken: 'jwt-abc',
        refreshToken: 'refresh-xyz',
        tenant: const {
          'id': 'tenant-1',
          'owner_name': 'Ana',
          'business_name': 'Tienda Ana',
          'business_type': 'minimercado',
          'charge_mode': 'pre_payment',
          'store_slug': 'tienda-ana',
          'logo_url': '',
        },
      );

      expect(probe.totalWrites, greaterThan(1));
      expect(probe.maxConcurrentWrites, 1,
          reason: 'saveSession también debe escribir en serie');
    });

    test('saveLegacySession no deja dos escrituras en vuelo a la vez',
        () async {
      await auth.saveLegacySession(
        token: 'jwt-abc',
        tenantId: 'tenant-1',
        ownerName: 'Ana',
        businessName: 'Tienda Ana',
        featureFlags: const {'enable_tables': false},
        businessTypes: const ['minimercado'],
      );

      expect(probe.totalWrites, greaterThan(1));
      expect(probe.maxConcurrentWrites, 1);
    });

    test('saveTokens no deja dos escrituras en vuelo a la vez', () async {
      await auth.saveTokens(
        accessToken: 'jwt-new',
        refreshToken: 'refresh-new',
      );

      expect(probe.totalWrites, greaterThan(1));
      expect(probe.maxConcurrentWrites, 1);
    });

    test('el token persiste y se puede leer de vuelta tras saveWorkspaceSession',
        () async {
      await auth.saveWorkspaceSession(
        accessToken: 'jwt-readable',
        refreshToken: 'refresh-xyz',
        tenantId: 'tenant-1',
        ownerName: 'Ana',
        businessName: 'Tienda Ana',
      );

      expect(await auth.getToken(), 'jwt-readable');
      expect(await auth.getRefreshToken(), 'refresh-xyz');
    });
  });
}
