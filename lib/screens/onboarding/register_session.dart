// Spec: specs/101-retocar-fotos-inventario/spec.md (fix 401 chip retoque)
//
// Persistencia de la sesión que devuelve POST /tenant/register.
//
// CAUSA RAÍZ del bug "chip Fotos sin retocar / retouch summary": el backend
// responde workspace-shape (AuthResponse, handlers/auth.go) con TODOS los
// campos TOP-LEVEL — `access_token`, `tenant_id`, `owner_name`,
// `business_name`, `role`, `branch_id`, `user_id`, capacidades Spec 051 —
// y SIN mapa anidado `tenant`. El callback viejo construía el tenant con
// `data['tenant']` (inexistente) → `{}` → `saveSession` persistía
// `vendia_tenant_id = ''` y toda pantalla que dependa del tenant local
// (p. ej. ManageInventoryScreen._loadTenantId, Spec 101) quedaba muda.
//
// Este helper parsea la respuesta REAL igual que login_screen.dart (mismo
// contrato, mismo fold de capacidades Spec 051) y usa saveWorkspaceSession
// para que rol/branch/user también aterricen en storage.

import '../../services/auth_service.dart';
import '../../utils/login_capability_flags.dart';

/// Persiste en [auth] la sesión devuelta por el registro de tenant.
///
/// Acepta las dos formas del backend:
/// - workspace-shape (`access_token` presente): campos top-level → se
///   guarda con [AuthService.saveWorkspaceSession] (paridad con el login).
/// - legacy (solo `token`): → [AuthService.saveLegacySession].
Future<void> persistRegisterSession(
  AuthService auth,
  Map<String, dynamic> data,
) async {
  // Spec 051: las capacidades nuevas viajan top-level, no dentro de
  // `feature_flags` — el fold evita degradar módulos activos al persistir.
  final featureFlags = foldLoginCapabilityFlags(data);
  final businessTypes =
      (data['business_types'] as List?)?.whereType<String>().toList();
  final creditLabelMode = data['credit_label_mode'] as String?;
  // F036: solo se propaga si el backend lo envía (deploys viejos no).
  final onboardingCompleted = data.containsKey('onboarding_completed')
      ? data['onboarding_completed'] == true
      : null;

  final accessToken = (data['access_token'] as String?) ?? '';
  if (accessToken.isNotEmpty) {
    await auth.saveWorkspaceSession(
      accessToken: accessToken,
      refreshToken: data['refresh_token'] as String? ?? '',
      tenantId: (data['tenant_id'] ?? '').toString(),
      ownerName: data['owner_name'] as String? ?? '',
      businessName: data['business_name'] as String? ?? '',
      userId: (data['user_id'] ?? '').toString(),
      branchId: (data['branch_id'] ?? '').toString(),
      role: data['role'] as String? ?? '',
      featureFlags: featureFlags,
      businessTypes: businessTypes,
      creditLabelMode: creditLabelMode,
      onboardingCompleted: onboardingCompleted,
    );
    return;
  }

  await auth.saveLegacySession(
    token: (data['token'] as String?) ?? '',
    tenantId: (data['tenant_id'] ?? '').toString(),
    ownerName: data['owner_name'] as String? ?? '',
    businessName: data['business_name'] as String? ?? '',
    featureFlags: featureFlags,
    businessTypes: businessTypes,
    creditLabelMode: creditLabelMode,
    onboardingCompleted: onboardingCompleted,
  );
}
