import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages JWT lifecycle and tenant session data securely.
/// iOS: Keychain | Android: EncryptedSharedPreferences.
/// Supports access + refresh token pair per the API contract.
class AuthService {
  static const _keyAccessToken = 'vendia_jwt';
  static const _keyRefreshToken = 'vendia_refresh_token';
  static const _keyTenantId = 'vendia_tenant_id';
  static const _keyOwnerName = 'vendia_owner_name';
  static const _keyBusinessName = 'vendia_business_name';
  static const _keyBusinessType = 'vendia_business_type';
  static const _keyChargeMode = 'vendia_charge_mode';
  static const _keyStoreSlug = 'vendia_store_slug';
  static const _keyLogoUrl = 'vendia_logo_url';
  static const _keyUserId = 'vendia_user_id';
  static const _keyBranchId = 'vendia_branch_id';
  static const _keyRole = 'vendia_role';
  // Feature flags + business types arrive on login/register (migration 021)
  // and drive conditional rendering (hide Tables/KDS for tiendas, show
  // "Cobrar Servicio" for reparación/manufactura, etc.). Persisted as
  // JSON so a single key covers the six-flag struct + the string array.
  static const _keyFeatureFlags = 'vendia_feature_flags';
  static const _keyBusinessTypes = 'vendia_business_types';
  // F028: copy configurable fiar/crédito. Persisted alongside feature flags
  // so the app can resolve labels offline without any extra round-trip.
  // Default 'fiar' when the key is absent (legacy tenants, pre-F028).
  static const _keyCreditLabelMode = 'vendia_credit_label_mode';

  final FlutterSecureStorage _storage;

  AuthService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions:
              IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  // ── Persistencia de sesión ────────────────────────────────────────────────
  //
  // F011 — TODAS las escrituras de sesión van EN SERIE, nunca con
  // `Future.wait`. En web, `flutter_secure_storage_web` genera la clave AES
  // (`localStorage['FlutterSecureStorage']`) con un check-then-act: dos
  // escrituras concurrentes en la primera sesión generan claves distintas y
  // la última sobrescribe a la anterior, dejando huérfanos los valores ya
  // cifrados → `getToken()` revienta luego con `OperationError`. Escribir
  // en serie garantiza que la primera escritura fija la clave AES y todas las
  // demás la reutilizan. En móvil el cambio es funcionalmente neutro.
  // Ver specs/011-web-auth-token/spec.md §2.

  Future<void> _saveFeatureFlags(Map<String, dynamic> source) async {
    final flags = source['feature_flags'];
    final types = source['business_types'];
    await _storage.write(
      key: _keyFeatureFlags,
      value: flags is Map ? jsonEncode(flags) : null,
    );
    await _storage.write(
      key: _keyBusinessTypes,
      value: types is List ? jsonEncode(types) : null,
    );
    // F028: persist credit_label_mode — default 'fiar' when absent.
    final mode = source['credit_label_mode'];
    await _storage.write(
      key: _keyCreditLabelMode,
      value: (mode == 'credit') ? 'credit' : 'fiar',
    );
  }

  /// Save full session after login/register (new contract with refresh tokens).
  ///
  /// Escrituras EN SERIE — ver nota F011 arriba.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> tenant,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(
        key: _keyTenantId, value: tenant['id']?.toString() ?? '');
    await _storage.write(
        key: _keyOwnerName, value: tenant['owner_name']?.toString() ?? '');
    await _storage.write(
        key: _keyBusinessName,
        value: tenant['business_name']?.toString() ?? '');
    await _storage.write(
        key: _keyBusinessType,
        value: tenant['business_type']?.toString() ?? '');
    await _storage.write(
        key: _keyChargeMode, value: tenant['charge_mode']?.toString() ?? '');
    await _storage.write(
        key: _keyStoreSlug, value: tenant['store_slug']?.toString() ?? '');
    await _storage.write(
        key: _keyLogoUrl, value: tenant['logo_url']?.toString() ?? '');
    await _saveFeatureFlags(tenant);
    // Warm in-memory cache after persistence so CreditLabels.of() resolves
    // synchronously from the first paint after login.
    final mode = tenant['credit_label_mode'];
    _creditLabelModeCache = (mode == 'credit') ? 'credit' : 'fiar';
  }

  /// Legacy save for backward compatibility (old format).
  ///
  /// Escrituras EN SERIE — ver nota F011 arriba.
  Future<void> saveLegacySession({
    required String token,
    required String tenantId,
    required String ownerName,
    required String businessName,
    Map<String, dynamic>? featureFlags,
    List<String>? businessTypes,
    String? creditLabelMode,
  }) async {
    await _storage.write(key: _keyAccessToken, value: token);
    await _storage.write(key: _keyTenantId, value: tenantId);
    await _storage.write(key: _keyOwnerName, value: ownerName);
    await _storage.write(key: _keyBusinessName, value: businessName);
    await _saveFeatureFlags({
      'feature_flags': featureFlags,
      'business_types': businessTypes,
      'credit_label_mode': creditLabelMode,
    });
    _creditLabelModeCache = (creditLabelMode == 'credit') ? 'credit' : 'fiar';
  }

  /// Save new token pair after refresh.
  ///
  /// Escrituras EN SERIE — ver nota F011 arriba.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  Future<String?> getToken() => _storage.read(key: _keyAccessToken);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);
  Future<String?> getOwnerName() => _storage.read(key: _keyOwnerName);
  Future<String?> getBusinessName() => _storage.read(key: _keyBusinessName);
  Future<String?> getBusinessType() => _storage.read(key: _keyBusinessType);
  Future<String?> getChargeMode() => _storage.read(key: _keyChargeMode);
  Future<String?> getStoreSlug() => _storage.read(key: _keyStoreSlug);
  Future<String?> getLogoUrl() => _storage.read(key: _keyLogoUrl);

  /// Update cached logo URL after upload.
  Future<void> updateLogoUrl(String url) =>
      _storage.write(key: _keyLogoUrl, value: url);

  Future<String?> getTenantId() async {
    return _storage.read(key: _keyTenantId);
  }

  /// Check if user has active session.
  Future<bool> hasSession() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Is this a bar/restaurant (enables tables, KDS, waiters, rockola)?
  Future<bool> isBarMode() async {
    final type = await getBusinessType();
    return type == 'bar';
  }

  /// Is post-payment mode (open accounts)?
  Future<bool> isPostPayment() async {
    final mode = await getChargeMode();
    return mode == 'post_payment';
  }

  /// Save workspace session after workspace selection.
  ///
  /// Escrituras EN SERIE — ver nota F011 arriba.
  Future<void> saveWorkspaceSession({
    required String accessToken,
    required String refreshToken,
    required String tenantId,
    required String ownerName,
    required String businessName,
    String userId = '',
    String branchId = '',
    String role = '',
    Map<String, dynamic>? featureFlags,
    List<String>? businessTypes,
    String? creditLabelMode,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyTenantId, value: tenantId);
    await _storage.write(key: _keyOwnerName, value: ownerName);
    await _storage.write(key: _keyBusinessName, value: businessName);
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyBranchId, value: branchId);
    await _storage.write(key: _keyRole, value: role);
    await _saveFeatureFlags({
      'feature_flags': featureFlags,
      'business_types': businessTypes,
      'credit_label_mode': creditLabelMode,
    });
    _creditLabelModeCache = (creditLabelMode == 'credit') ? 'credit' : 'fiar';
  }

  /// Feature flags retrieved at last login. Missing keys default to
  /// false — legacy tenants that predate migration 021 behave as if
  /// every module is disabled, which is safe (modules hide rather than
  /// expose new UI by accident).
  Future<FeatureFlags> getFeatureFlags() async {
    final raw = await _storage.read(key: _keyFeatureFlags);
    if (raw == null || raw.isEmpty) return const FeatureFlags();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return FeatureFlags.fromJson(decoded);
      }
    } catch (_) {
      // Corrupted blob — fall through to defaults so we never crash
      // the UI on malformed storage.
    }
    return const FeatureFlags();
  }

  /// Business types selected during onboarding. Empty list when the
  /// tenant predates migration 020 and never picked any.
  Future<List<String>> getBusinessTypes() async {
    final raw = await _storage.read(key: _keyBusinessTypes);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // Ignore and fall through to empty list.
    }
    return const [];
  }

  Future<String?> getUserId() => _storage.read(key: _keyUserId);
  Future<String?> getBranchId() => _storage.read(key: _keyBranchId);
  Future<void> saveBranchId(String id) => _storage.write(key: _keyBranchId, value: id);
  Future<String?> getRole() => _storage.read(key: _keyRole);

  // F028 — credit_label_mode ─────────────────────────────────────────────

  /// In-memory cache so [CreditLabels.of(context)] can resolve labels
  /// synchronously (no async gap between load and first paint).
  /// Populated at login via [_saveFeatureFlags] → awaited in [saveSession].
  /// Falls back to 'fiar' (pre-F028 retrocompat).
  String _creditLabelModeCache = 'fiar';

  /// Synchronous getter used by [CreditLabels.of].
  String get creditLabelMode => _creditLabelModeCache;

  /// Warm the in-memory cache from secure storage. Call once after
  /// [AuthService] is instantiated (e.g. in app bootstrap or Provider).
  Future<void> loadCreditLabelMode() async {
    final raw = await _storage.read(key: _keyCreditLabelMode);
    _creditLabelModeCache = (raw == 'credit') ? 'credit' : 'fiar';
  }

  /// Update the cache and persist immediately (called after a successful
  /// PATCH /store/profile that changes credit_label_mode).
  Future<void> updateCreditLabelMode(String mode) async {
    final normalized = (mode == 'credit') ? 'credit' : 'fiar';
    _creditLabelModeCache = normalized;
    await _storage.write(key: _keyCreditLabelMode, value: normalized);
  }

  /// Logout — clear all secure storage.
  Future<void> logout() => _storage.deleteAll();
}

/// Mirror of the backend `models.FeatureFlags` struct (migration 021).
/// Values default to false so the UI fails closed when the blob is
/// missing — new modules do not appear by accident for legacy tenants.
class FeatureFlags {
  final bool enableTables;
  final bool enableKDS;
  final bool enableTips;
  final bool enableServices;
  final bool enableCustomBilling;
  final bool enableFractionalUnits;

  /// F029: precios multi-tier por tipo de cliente.
  /// Cuando es `true` la UI muestra 3 inputs adicionales en
  /// crear/editar producto (más allá del retail) y un selector
  /// "Tipo de precio" en Confirmar Venta.
  final bool enablePriceTiers;

  const FeatureFlags({
    this.enableTables = false,
    this.enableKDS = false,
    this.enableTips = false,
    this.enableServices = false,
    this.enableCustomBilling = false,
    this.enableFractionalUnits = false,
    this.enablePriceTiers = false,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> json) => FeatureFlags(
        enableTables: json['enable_tables'] == true,
        enableKDS: json['enable_kds'] == true,
        enableTips: json['enable_tips'] == true,
        enableServices: json['enable_services'] == true,
        enableCustomBilling: json['enable_custom_billing'] == true,
        enableFractionalUnits: json['enable_fractional_units'] == true,
        // F029 — default false para tenants pre-migración: la UI fail-closed
        // (no aparecen inputs ni selector) hasta que el dueño lo prenda.
        enablePriceTiers: json['enable_price_tiers'] == true,
      );
}
