// Spec: specs/101-retocar-fotos-inventario/spec.md (fix 401 chip retoque)
//
// CAUSA RAÍZ del bug "chip Fotos sin retocar inaccesible / summary 401":
// POST /tenant/register responde workspace-shape (AuthResponse del backend:
// `access_token`, `tenant_id`, `owner_name`, `business_name`… TOP-LEVEL,
// SIN mapa anidado `tenant`), pero el callback saveSession de
// onboarding_stepper.dart construía el tenant con `data['tenant']` → `{}`
// → `AuthService.saveSession` persistía `vendia_tenant_id = ''` (y
// business_type, charge_mode, store_slug, logo_url vacíos; user_id,
// branch_id y role ni se escribían). Confirmado en prod: storage del
// tenant e6d3effd ("Ropa Test QA") con exactamente esa huella.
//
// Estos tests fijan el contrato de `persistRegisterSession`: la respuesta
// REAL del register debe dejar una sesión completa en storage.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/onboarding/register_session.dart';
import 'package:vendia_pos/services/auth_service.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

/// Respuesta REAL de POST /tenant/register (backend AuthResponse,
/// handlers/auth.go): todo top-level, sin mapa `tenant`.
Map<String, dynamic> _workspaceShapeRegisterResponse() => {
      'token': 'jwt-legacy-alias',
      'access_token': 'jwt-abc',
      'refresh_token': 'refresh-xyz',
      'tenant_id': 'e6d3effd-b870-47b1-8c88-ccc046615d7b',
      'owner_name': 'María Gómez',
      'business_name': 'Ropa Test QA Variantes',
      'business_types': ['emprendimiento_general'],
      'feature_flags': {'enable_services': true},
      'credit_label_mode': 'fiar',
      'enable_product_variants': true,
      'role': 'owner',
      'branch_id': 'branch-1',
      'user_id': 'user-1',
      'onboarding_completed': false,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SecureStorageMock storage;
  late AuthService auth;

  setUp(() {
    storage = _SecureStorageMock()..install();
    auth = AuthService();
  });

  tearDown(() => storage.uninstall());

  group('persistRegisterSession — respuesta workspace-shape (la real)', () {
    test('persiste el tenant_id TOP-LEVEL (el bug lo dejaba vacío)',
        () async {
      await persistRegisterSession(auth, _workspaceShapeRegisterResponse());

      expect(await auth.getTenantId(),
          'e6d3effd-b870-47b1-8c88-ccc046615d7b');
    });

    test('persiste tokens, nombres, rol y contexto de workspace', () async {
      await persistRegisterSession(auth, _workspaceShapeRegisterResponse());

      expect(await auth.getToken(), 'jwt-abc');
      expect(await auth.getRefreshToken(), 'refresh-xyz');
      expect(await auth.getOwnerName(), 'María Gómez');
      expect(await auth.getBusinessName(), 'Ropa Test QA Variantes');
      expect(await auth.getRole(), 'owner');
      expect(await auth.getBranchId(), 'branch-1');
      expect(await auth.getUserId(), 'user-1');
    });

    test('capacidades top-level (Spec 051) no se pierden al registrar',
        () async {
      await persistRegisterSession(auth, _workspaceShapeRegisterResponse());

      final flags = await auth.getFeatureFlags();
      expect(flags.enableServices, isTrue,
          reason: 'feature_flags JSONB debe persistirse');
      // enable_product_variants viaja TOP-LEVEL (no en el JSONB): el fold
      // de Spec 051 debe rescatarlo igual que en el login.
      final raw = storage.store['vendia_feature_flags'] ?? '';
      expect(raw, contains('enable_product_variants'));
    });

    test('onboarding_completed=false del registro se respeta (F036)',
        () async {
      await persistRegisterSession(auth, _workspaceShapeRegisterResponse());

      expect(await auth.getOnboardingCompleted(), isFalse);
    });
  });

  group('persistRegisterSession — respuesta legacy (sin access_token)', () {
    test('cae a saveLegacySession con los campos top-level', () async {
      await persistRegisterSession(auth, {
        'token': 'jwt-legacy',
        'tenant_id': 'tenant-legacy',
        'owner_name': 'Ana',
        'business_name': 'Tienda Ana',
      });

      expect(await auth.getToken(), 'jwt-legacy');
      expect(await auth.getTenantId(), 'tenant-legacy');
      expect(await auth.getOwnerName(), 'Ana');
    });
  });
}
