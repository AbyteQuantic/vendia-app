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

  final FlutterSecureStorage _storage;

  AuthService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions:
              IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  /// Save full session after login/register (new contract with refresh tokens).
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> tenant,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyTenantId, value: tenant['id']?.toString() ?? ''),
      _storage.write(
          key: _keyOwnerName, value: tenant['owner_name']?.toString() ?? ''),
      _storage.write(
          key: _keyBusinessName,
          value: tenant['business_name']?.toString() ?? ''),
      _storage.write(
          key: _keyBusinessType,
          value: tenant['business_type']?.toString() ?? ''),
      _storage.write(
          key: _keyChargeMode,
          value: tenant['charge_mode']?.toString() ?? ''),
      _storage.write(
          key: _keyStoreSlug, value: tenant['store_slug']?.toString() ?? ''),
      _storage.write(
          key: _keyLogoUrl, value: tenant['logo_url']?.toString() ?? ''),
    ]);
  }

  /// Legacy save for backward compatibility (old format).
  Future<void> saveLegacySession({
    required String token,
    required int tenantId,
    required String ownerName,
    required String businessName,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: token),
      _storage.write(key: _keyTenantId, value: tenantId.toString()),
      _storage.write(key: _keyOwnerName, value: ownerName),
      _storage.write(key: _keyBusinessName, value: businessName),
    ]);
  }

  /// Save new token pair after refresh.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
    ]);
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

  Future<int?> getTenantId() async {
    final v = await _storage.read(key: _keyTenantId);
    return v != null ? int.tryParse(v) : null;
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

  /// Logout — clear all secure storage.
  Future<void> logout() => _storage.deleteAll();
}
