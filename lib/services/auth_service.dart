import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/login_capability_flags.dart';

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
  // Teléfono con el que inició sesión el usuario ACTUAL (no el dueño). Enlaza
  // la sesión con su fila Employee (backend liga User↔Employee por phone+tenant)
  // para que el Dashboard muestre la foto/nombre del usuario logueado y no
  // siempre los del dueño. Se guarda en el login (cubre login directo y el
  // selector de workspace) y se borra en logout (deleteAll).
  static const _keyPhone = 'vendia_phone';
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
  // F036: flag de onboarding. Persistido para decidir post-login si se
  // muestra el wizard de configuración inicial. Default 'true' cuando la
  // clave está ausente — un tenant que ya viene usando la app (o cuya
  // sesión es pre-F036) NO debe ver el wizard.
  static const _keyOnboardingCompleted = 'vendia_onboarding_completed';

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

  /// Refresca el cache local de `feature_flags` + `business_types` a
  /// partir del shape que devuelve `GET/PATCH /api/v1/store/profile`.
  /// Lo usa `CapabilityScaffold` después de activar/desactivar una
  /// capacidad para que el Dashboard vea el cambio al volver — el
  /// Dashboard lee de disco vía [getFeatureFlags], no del backend.
  ///
  /// Falla silenciosa: si el shape no trae `feature_flags`, el cache
  /// queda como estaba.
  Future<void> saveFeatureFlagsFromProfile(
      Map<String, dynamic> profile) async {
    await _saveFeatureFlags(profile);
  }

  Future<void> _saveFeatureFlags(Map<String, dynamic> source) async {
    // El backend devuelve un shape mixto: `feature_flags` es un
    // sub-objeto JSONB con los flags VIEJOS (kds/tips/tables/services/
    // custom_billing/fractional_units), pero los flags NUEVOS
    // (enable_marketing_hub, enable_quotes, enable_promotions, etc.
    // — todo lo agregado por F029-F037) viven como columnas
    // top-level del tenant. Si solo persistimos `source['feature_flags']`
    // perdemos los nuevos y el Dashboard nunca los ve hasta el
    // siguiente PATCH (que tampoco los persistía hasta hoy).
    //
    // Solución: mergear ambos en un mismo blob antes de escribir a
    // disco. `FeatureFlags.fromJson` ya entiende las dos formas.
    // Mergea el sub-objeto feature_flags (7 viejos) + las capacidades
    // top-level (Spec 051). Misma lógica que el login.
    final merged = foldLoginCapabilityFlags(source);
    final types = source['business_types'];
    // GUARDA NO-DESTRUCTIVA (Spec 051 — bug crítico): el PATCH /store/profile
    // responde SOLO {"message": ...} (sin flags). Pasar esa respuesta aquí
    // dejaba `merged` vacío y el código viejo escribía `null` → BORRABA todas
    // las capacidades del cache (se "apagaban" todos los módulos hasta el
    // próximo GET). Ahora: si el source no trae info de flags, NO tocamos el
    // cache existente. El camino correcto tras un PATCH es re-hacer GET (lo
    // hace refreshFeatureFlagsFromServer) — esto es defensa en profundidad.
    if (merged.isNotEmpty) {
      await _storage.write(key: _keyFeatureFlags, value: jsonEncode(merged));
    }
    // Solo sobrescribimos los tipos cuando el source TRAE el array. El
    // login envía `business_type` (singular) pero NO `business_types`
    // (plural), y antes esto nulaba la cache en cada login aunque el
    // tenant tuviera varios tipos. Igual criterio que `onboarding_completed`.
    if (types is List) {
      await _storage.write(key: _keyBusinessTypes, value: jsonEncode(types));
    }
    // F028: persist credit_label_mode SOLO cuando el source lo trae. Antes
    // escribía 'fiar' por defecto aunque el source no lo incluyera (p.ej. la
    // respuesta {message} del PATCH) → reseteaba a 'fiar' un tenant 'credit'.
    if (source.containsKey('credit_label_mode')) {
      final mode = source['credit_label_mode'];
      await _storage.write(
        key: _keyCreditLabelMode,
        value: (mode == 'credit') ? 'credit' : 'fiar',
      );
    }
    // F036: persist onboarding_completed. Only write when the source
    // actually carries the field — a login response without it (legacy
    // backend pre-F036) must NOT overwrite a previously-stored value.
    if (source.containsKey('onboarding_completed')) {
      await _storage.write(
        key: _keyOnboardingCompleted,
        value: (source['onboarding_completed'] == true) ? 'true' : 'false',
      );
    }
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
    bool? onboardingCompleted,
  }) async {
    await _storage.write(key: _keyAccessToken, value: token);
    await _storage.write(key: _keyTenantId, value: tenantId);
    await _storage.write(key: _keyOwnerName, value: ownerName);
    await _storage.write(key: _keyBusinessName, value: businessName);
    await _saveFeatureFlags({
      'feature_flags': featureFlags,
      'business_types': businessTypes,
      'credit_label_mode': creditLabelMode,
      // F036: solo se incluye la clave si el caller pasó el valor —
      // _saveFeatureFlags omite la escritura si la clave está ausente.
      if (onboardingCompleted != null)
        'onboarding_completed': onboardingCompleted,
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

  /// Re-cachea solo el nombre del dueño/negocio (cuando se rescatan del backend
  /// porque el login/select-workspace los dejó vacíos). Spec 078 council.
  Future<void> cacheProfileNames(String owner, String business) async {
    if (owner.isNotEmpty) await _storage.write(key: _keyOwnerName, value: owner);
    if (business.isNotEmpty) {
      await _storage.write(key: _keyBusinessName, value: business);
    }
  }
  Future<String?> getBusinessType() => _storage.read(key: _keyBusinessType);
  Future<String?> getChargeMode() => _storage.read(key: _keyChargeMode);
  Future<String?> getStoreSlug() => _storage.read(key: _keyStoreSlug);
  Future<String?> getLogoUrl() => _storage.read(key: _keyLogoUrl);

  /// Update cached logo URL after upload.
  Future<void> updateLogoUrl(String url) =>
      _storage.write(key: _keyLogoUrl, value: url);

  /// Persiste SOLO la lista de tipos de negocio, sin tocar los feature
  /// flags. Útil cuando el Dashboard sincroniza los tipos desde el
  /// backend (`fetchBusinessProfile`) — el login trae `business_type`
  /// singular pero NO el array `business_types`, así que la cache quedaba
  /// vacía. No usar `saveFeatureFlagsFromProfile` para esto: ese merge
  /// podría borrar los flags si la respuesta no los incluye.
  Future<void> setBusinessTypes(List<String> types) => _storage.write(
        key: _keyBusinessTypes,
        value: types.isEmpty ? null : jsonEncode(types),
      );

  Future<String?> getTenantId() async {
    final stored = await _storage.read(key: _keyTenantId);
    if (stored != null && stored.trim().isNotEmpty) return stored;
    // Auto-reparación (fix 101-retouch-401): el registro workspace-shape
    // persistía tenant_id VACÍO (parseaba un mapa `tenant` inexistente).
    // Las sesiones que quedaron así en producción se reparan solas: el
    // claim `tenant_id` del JWT (que el backend ya validó al emitirlo) es
    // la fuente de verdad; se re-persiste para que la siguiente lectura
    // sea directa. Sin JWT o sin claim, se devuelve lo guardado.
    final claim = tenantIdFromJwt(await getToken());
    if (claim.isEmpty) return stored;
    await _storage.write(key: _keyTenantId, value: claim);
    return claim;
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
    bool? onboardingCompleted,
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
      // F036: ver nota en saveLegacySession.
      if (onboardingCompleted != null)
        'onboarding_completed': onboardingCompleted,
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

  /// F036: ¿completó el dueño el onboarding inicial?
  ///
  /// Default `true` cuando la clave está ausente — un tenant cuya sesión
  /// es pre-F036, o que ya venía usando la app, NO debe ver el wizard.
  /// Solo un registro nuevo (que recibe `onboarding_completed=false` del
  /// backend) lo verá.
  Future<bool> getOnboardingCompleted() async {
    final raw = await _storage.read(key: _keyOnboardingCompleted);
    if (raw == null) return true;
    return raw != 'false';
  }

  /// F036: marca el onboarding como completado y persiste de inmediato.
  /// Se llama tras el PATCH /store/profile exitoso del wizard (al
  /// terminar o saltar).
  Future<void> updateOnboardingCompleted(bool completed) =>
      _storage.write(
        key: _keyOnboardingCompleted,
        value: completed ? 'true' : 'false',
      );

  Future<String?> getUserId() => _storage.read(key: _keyUserId);

  /// Persiste el teléfono del usuario que inició sesión. Se llama en el login,
  /// antes de ramificar a selector/dashboard, así que cubre todos los caminos.
  Future<void> savePhone(String phone) =>
      _storage.write(key: _keyPhone, value: phone);

  /// Teléfono del usuario logueado (para resolver su fila Employee → foto/nombre).
  Future<String?> getPhone() => _storage.read(key: _keyPhone);

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

  /// Spec 105 F3 — "el mesero puede cobrar": OFF = mesero puro (solo mesas
  /// y entregas); ON agrega Registrar Venta a la vista del mesero.
  final bool enableWaiterCharge;
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

  /// Spec 095: variantes de producto (talla/color). Cuando es `true`,
  /// Nuevo/Editar Producto muestra el generador de combinaciones y el POS
  /// muestra el selector de variante. Default false — un tenant que no la
  /// activa ve la app IDÉNTICA a hoy (AC-01).
  final bool enableProductVariants;

  /// F030: gestión de clientes identificados.
  /// Cuando es `true` el checkout muestra un tile "Cliente", el menú
  /// principal muestra "Mis clientes" y toda venta puede asociarse a
  /// un cliente. Espejo del backend `tenants.enable_customer_management`.
  final bool enableCustomerManagement;

  /// F031: módulo de cotizaciones.
  /// Cuando es `true` el menú principal muestra "Cotizaciones" y el
  /// dueño puede armar/enviar/convertir cotizaciones. Espejo del backend
  /// `tenants.enable_quotes`. Default OFF.
  final bool enableQuotes;

  /// F033: módulo de difusión de promociones.
  /// Cuando es `true` el menú principal muestra "Promociones" y el
  /// dueño puede armar campañas y enviarlas por WhatsApp / link. Espejo
  /// del backend `tenants.enable_promotions`. Default OFF.
  final bool enablePromotions;

  /// F037: Marketing Hub — combos, banners IA y catálogo en línea.
  /// Antes era core (F036); F037 lo migra a opt-in para dejar el
  /// Dashboard inicial ultra-simple. Espejo de
  /// `tenants.enable_marketing_hub`. Default OFF.
  final bool enableMarketingHub;

  /// F037: recetas para fabricar productos terminados.
  /// Antes era byType (cooking); F037 lo migra a opt-in. Tenants con
  /// recetas preexistentes quedaron en true por el backfill. Espejo
  /// de `tenants.enable_recipes`. Default OFF.
  final bool enableRecipes;

  /// F037: insumos / materia prima.
  /// Antes era byType (cooking); F037 lo migra a opt-in. Backfill activa
  /// para tenants con filas en `ingredients`. Espejo de
  /// `tenants.enable_supplies`. Default OFF.
  final bool enableSupplies;

  /// F037: trabajos de muebles / por encargo.
  /// Antes era byType (furniture); F037 lo migra a opt-in. Backfill
  /// activa para tenants con filas en `work_orders`. Espejo de
  /// `tenants.enable_furniture_jobs`. Default OFF.
  final bool enableFurnitureJobs;

  /// F037: órdenes de compra a proveedores.
  /// Antes era byType (cooking); F037 lo migra a opt-in. Backfill activa
  /// para tenants con filas en `purchase_orders`. Espejo de
  /// `tenants.enable_purchase_orders`. Default OFF.
  final bool enablePurchaseOrders;

  /// F042: módulo de eventos (cursos / conferencias / hackatones).
  /// Self-activado por el tendero desde el reel "Descubre más opciones".
  /// Espejo de `tenants.feature_flags.enable_events`. Default OFF.
  final bool enableEvents;

  /// Spec 075: modo proveedor ("Vendo a tiendas"). Lo prenden los
  /// business_type proveedor_agricola / proveedor_mayorista. Habilita el
  /// Panel de proveedor (pedidos entrantes + anti-merma). Default OFF.
  final bool enableSupplierMode;

  /// Spec 084: comisiones/liquidación a profesionales (peluquería/barbería).
  /// Gatilla la atribución de servicios por profesional y la liquidación.
  /// Espejo de `tenants.feature_flags.enable_staff_commissions`. Default OFF.
  final bool enableStaffCommissions;

  const FeatureFlags({
    this.enableTables = false,
    this.enableKDS = false,
    this.enableTips = false,
    this.enableServices = false,
    this.enableCustomBilling = false,
    this.enableFractionalUnits = false,
    this.enablePriceTiers = false,
    this.enableProductVariants = false,
    this.enableCustomerManagement = false,
    this.enableQuotes = false,
    this.enablePromotions = false,
    this.enableMarketingHub = false,
    this.enableRecipes = false,
    this.enableSupplies = false,
    this.enableFurnitureJobs = false,
    this.enablePurchaseOrders = false,
    this.enableEvents = false,
    this.enableSupplierMode = false,
    this.enableStaffCommissions = false,
    this.enableWaiterCharge = false,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> json) => FeatureFlags(
        enableTables: json['enable_tables'] == true,
        enableWaiterCharge: json['enable_waiter_charge'] == true,
        enableKDS: json['enable_kds'] == true,
        enableTips: json['enable_tips'] == true,
        enableServices: json['enable_services'] == true,
        enableCustomBilling: json['enable_custom_billing'] == true,
        enableFractionalUnits: json['enable_fractional_units'] == true,
        // F029 — default false para tenants pre-migración: la UI fail-closed
        // (no aparecen inputs ni selector) hasta que el dueño lo prenda.
        enablePriceTiers: json['enable_price_tiers'] == true,
        // Spec 095 — default false para tenants que nunca la activaron.
        enableProductVariants: json['enable_product_variants'] == true,
        // F030 — default false: tenants pre-migración no ven la
        // funcionalidad de clientes hasta que el dueño la prenda (AC-07).
        enableCustomerManagement: json['enable_customer_management'] == true,
        // F031 — default false: la app es idéntica a hoy hasta que el
        // dueño prenda la capacidad de cotizaciones (AC-13).
        enableQuotes: json['enable_quotes'] == true,
        // F033 — default false: con la capacidad OFF no aparece UI nueva
        // (AC-11).
        enablePromotions: json['enable_promotions'] == true,
        // F037 — default false: con la capacidad OFF Marketing Hub queda
        // como opción descubrible en el reel del Dashboard.
        enableMarketingHub: json['enable_marketing_hub'] == true,
        // F037 — default false; backfill las prende para tenants con
        // datos legacy en cada módulo (Art. X, idempotente).
        enableRecipes: json['enable_recipes'] == true,
        enableSupplies: json['enable_supplies'] == true,
        enableFurnitureJobs: json['enable_furniture_jobs'] == true,
        enablePurchaseOrders: json['enable_purchase_orders'] == true,
        // F042 — default false: el módulo de eventos se activa self-service.
        enableEvents: json['enable_events'] == true,
        // Spec 075 — viaja dentro de feature_flags.
        enableSupplierMode: json['enable_supplier_mode'] == true,
        // Spec 084 — comisiones/liquidación a profesionales.
        enableStaffCommissions: json['enable_staff_commissions'] == true,
      );
}

/// Extrae el claim `tenant_id` de un JWT SIN validar la firma — la firma la
/// valida el backend en cada request; aquí solo se lee el payload para la
/// auto-reparación de [AuthService.getTenantId]. Devuelve `''` si el token
/// es nulo, malformado o no trae el claim (p. ej. tokens legacy).
String tenantIdFromJwt(String? token) {
  if (token == null || token.isEmpty) return '';
  final parts = token.split('.');
  if (parts.length != 3) return '';
  try {
    final payload =
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      final v = decoded['tenant_id'];
      if (v is String) return v.trim();
    }
  } catch (_) {
    // Payload ilegible: no hay claim que rescatar.
  }
  return '';
}
