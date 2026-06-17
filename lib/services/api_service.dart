import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import '../config/supabase_config.dart';
import '../models/import_report.dart';
import '../models/subscription.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_upsell_sheet.dart';
import 'app_error.dart';
import 'auth_service.dart';
import 'cart_session_service.dart';
import 'cold_start_retry_interceptor.dart';
import 'image_normalizer.dart';

/// Central API client for the VendIA backend.
/// Integrates with the full contract: 18 modules, 70+ endpoints.
/// All protected endpoints auto-inject JWT via interceptor.
class ApiService {
  late final Dio _dio;
  final AuthService _auth;

  /// Delays between retries for [importCustomers].
  /// Injected as a test seam so tests run instantly.
  final List<Duration> _importRetryDelays;

  static const _kImportChunkSize = 100;
  static const _kImportMaxRetries = 3;

  static final GlobalKey<ScaffoldMessengerState> scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Active sede id (Phase-6 branch isolation). Updated by
  /// [BranchProvider.selectBranch] so every operational read / write
  /// can attach `?branch_id=` (GETs) or `branch_id` in the body
  /// (createSale) without each widget wiring through Provider.
  ///
  /// Null means "mono-sede tenant / context not loaded yet" — the
  /// backend returns the legacy tenant-wide response in that case
  /// so nothing regresses. Tests set this directly to simulate the
  /// branch selector.
  static String? currentBranchId;

  ApiService(this._auth,
      {List<Duration>? importRetryDelays,
      @visibleForTesting bool addColdStartInterceptor = true})
      : _importRetryDelays = importRetryDelays ??
            const [
              Duration(seconds: 2),
              Duration(seconds: 5),
              Duration(seconds: 10),
            ] {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Auto-inject JWT for protected routes
        // Public store routes use slug pattern: /store/:slug/...
        final isPublicStore = RegExp(r'/store/[^/]+/(catalog|product|order)')
            .hasMatch(options.path);
        final isPublicRockola = options.path.contains('/rockola/') &&
            options.path.contains('/suggest');
        final isPublicAccount = options.path.contains('/account/');

        final needsAuth = options.path.startsWith('/api/v1') &&
            !isPublicStore &&
            !isPublicAccount &&
            !isPublicRockola;

        if (needsAuth || options.path == '/api/v1/auth/logout') {
          final token = await _auth.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Soft paywall: the backend emits a structured payload on
        // premium-locked endpoints. Historical builds tagged it
        // `error_code: "premium_expired"`; the 2026-04-24 epic added
        // the canonical `error: "premium_feature_locked"` +
        // `code: 403` pair. We match on EITHER, so old + new
        // backend deploys coexist with this client.
        //
        // Basic endpoints (auth, sales, inventory) stay open so the
        // cashier keeps working while the owner considers the
        // upgrade — see migration 022 + middleware.PremiumAuth in Go.
        if (_isPremiumLocked(error)) {
          final reason = _extractErrorMessage(error);
          unawaited(PremiumUpsellController.notifyBlocked(reason: reason));
          handler.next(error);
          return;
        }

        if (error.response?.statusCode == 401 &&
            !error.requestOptions.path.contains('/auth/refresh') &&
            !error.requestOptions.path.contains('/login')) {
          // Try token refresh
          final refreshed = await _tryRefreshToken();
          if (refreshed) {
            // Retry the original request
            final opts = error.requestOptions;
            final token = await _auth.getToken();
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (_) {}
          }
          _auth.logout();
          scaffoldKey.currentState?.showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tu sesión expiró. Por favor inicia sesión de nuevo.',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.error,
              duration: Duration(seconds: 5),
            ),
          );
        }
        handler.next(error);
      },
    ));

    // Spec 012 — cold-start resilience. Registered AFTER the auth/
    // paywall interceptor on purpose: Dio runs error interceptors in
    // registration order, so the wrapper above still handles 401
    // (token refresh) and the soft-paywall 403 first. Only errors it
    // chooses to pass through reach this retry interceptor, which acts
    // solely on the transient cold-start shape (connectionError /
    // timeouts / 502-503-504). A 401 is never a cold start and is
    // never retried here. See cold_start_retry_interceptor.dart.
    if (addColdStartInterceptor) {
      _dio.interceptors.add(ColdStartRetryInterceptor(dio: _dio));
    }
  }

  /// Test seam (Spec 014): swap the underlying Dio HTTP adapter for a
  /// scripted one so request payloads can be asserted without hitting
  /// the network. Production code never calls this.
  @visibleForTesting
  set httpClientAdapterForTesting(HttpClientAdapter adapter) =>
      _dio.httpClientAdapter = adapter;

  Future<bool> _tryRefreshToken() async {
    try {
      final refreshToken = await _auth.getRefreshToken();
      if (refreshToken == null) return false;
      final response = await _dio.post('/api/v1/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      final data = response.data as Map<String, dynamic>;
      await _auth.saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/login', data: {
        'phone': phone,
        'password': password,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // Spec: specs/024-captcha-registro-login/spec.md (T-17)
  /// Variante de [login] que incluye el token de captcha en el body (F024).
  /// Usada por LoginScreen cuando TURNSTILE_SITE_KEY está activo.
  /// Si el backend rechaza el token, lanza [CaptchaFailedException].
  Future<Map<String, dynamic>> loginWithCaptcha({
    required String phone,
    required String password,
    String? captchaToken,
  }) async {
    try {
      final body = <String, dynamic>{
        'phone': phone,
        'password': password,
      };
      if (captchaToken != null && captchaToken.isNotEmpty) {
        body['captcha_token'] = captchaToken;
      }
      final response = await _dio.post('/login', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _throwIfCaptchaFailure(e);
      throw AppError.fromDioException(e);
    }
  }

  /// Select a workspace (multi-workspace flow). Requires temp_token as auth
  /// and the password specific to the chosen workspace — the backend rejects
  /// cross-tenant credential reuse with `workspace_password_mismatch`.
  Future<Map<String, dynamic>> selectWorkspace({
    required String workspaceId,
    required String tempToken,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/select-workspace',
        data: {
          'workspace_id': workspaceId,
          'password': password,
        },
        options: Options(headers: {'Authorization': 'Bearer $tempToken'}),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> registerTenantFull(
      Map<String, dynamic> payload) async {
    try {
      final response =
          await _dio.post('/api/v1/tenant/register', data: payload);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // Spec: specs/024-captcha-registro-login/spec.md (T-17)
  /// Variante de [registerTenantFull] que extrae [captchaToken] del payload
  /// o lo acepta como parámetro explícito (F024).
  /// Si el backend rechaza el token, lanza [CaptchaFailedException].
  Future<Map<String, dynamic>> registerTenantFullWithCaptcha(
    Map<String, dynamic> payload, {
    String? captchaToken,
  }) async {
    try {
      final body = Map<String, dynamic>.from(payload);
      if (captchaToken != null && captchaToken.isNotEmpty) {
        body['captcha_token'] = captchaToken;
      }
      final response = await _dio.post('/api/v1/tenant/register', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _throwIfCaptchaFailure(e);
      throw AppError.fromDioException(e);
    }
  }

  /// Lanza [CaptchaFailedException] si el error de Dio es un 400 de captcha.
  /// Llamar ANTES de `throw AppError.fromDioException(e)` en login/register.
  static void _throwIfCaptchaFailure(DioException e) {
    final status = e.response?.statusCode;
    if (status != 400) return;
    final data = e.response?.data;
    if (data is! Map) return;
    final msg = (data['error'] as String? ?? '').toLowerCase();
    if (msg.contains('verificación de seguridad') ||
        msg.contains('captcha') ||
        msg.contains('turnstile')) {
      throw CaptchaFailedException(data['error'] as String? ?? msg);
    }
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post('/api/v1/auth/logout', data: {
        'refresh_token': refreshToken,
      });
    } catch (_) {
      // Ignore — local logout still happens
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. BRANCHES (Sucursales)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns all branches for the authenticated tenant.
  Future<List<Map<String, dynamic>>> fetchBranches() async {
    try {
      final response = await _dio.get('/api/v1/store/branches');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Returns a single branch by its UUID.
  Future<Map<String, dynamic>> fetchBranch(String id) async {
    try {
      final response = await _dio.get('/api/v1/store/branches/$id');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Creates a new branch (sucursal). Required fields: `name`.
  /// Optional: `address`, `latitude`, `longitude`.
  Future<Map<String, dynamic>> createBranch(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/store/branches', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Updates an existing branch (name, address, coords, is_active).
  Future<Map<String, dynamic>> updateBranch(
      String id, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.patch('/api/v1/store/branches/$id', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Soft-deletes a branch. The backend prevents deleting the default
  /// branch (returns 422) and any branch that still has active employees.
  Future<void> deleteBranch(String id) async {
    try {
      await _dio.delete('/api/v1/store/branches/$id');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. EMPLOYEES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchEmployees() async {
    try {
      final response = await _dio.get('/api/v1/employees');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/employees', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateEmployee(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/employees/$uuid', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deleteEmployee(String uuid) async {
    try {
      await _dio.delete('/api/v1/employees/$uuid');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Owner-only: hand a temporary password to an employee so they can
  /// log in via phone+password. The backend also upserts a global
  /// User row + UserWorkspace so the next login picks up this tenant
  /// in the workspaces array. If the phone already belongs to a User
  /// (Viviana case: cashier here, owner elsewhere) the response sets
  /// `password_already_set=true` so the UI can warn the owner that
  /// the global credential was NOT overwritten.
  Future<Map<String, dynamic>> setEmployeePassword({
    required String employeeUuid,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/employees/$employeeUuid/password',
        data: {'password': password},
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> verifyPin({
    required String employeeUuid,
    required String pin,
  }) async {
    try {
      final response = await _dio.post('/api/v1/employees/verify-pin', data: {
        'employee_uuid': employeeUuid,
        'pin': pin,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Uploads a profile photo for the employee (or owner) [uuid].
  ///
  /// Spec 019 / FR-04, D2: takes an [XFile] — never a `dart:io File` —
  /// reads its BYTES and normalizes the image to a downsized **PNG** via
  /// [normalizeImageForUpload] before building the multipart part. This
  /// is the same `uploadProductPhoto` (F013) / `logoMultipart` (F010)
  /// pipeline, so it works on Flutter web (no filesystem, `XFile.path` is
  /// only a blob URL) and on iOS Safari (HEIC re-encoded to PNG).
  ///
  /// Sends the part as the `photo` field. The backend stores the image
  /// and returns `{data:{photo_url}}` (Plan 019 §4). Returns that data
  /// map so callers can read the new `photo_url`.
  ///
  /// Throws [ImageNormalizationException] (Spanish message) when the
  /// picked image cannot be decoded; callers surface it to the merchant.
  Future<Map<String, dynamic>> uploadEmployeePhoto(
      String uuid, XFile photo) async {
    try {
      final formData = FormData.fromMap({
        'photo': await _imageMultipart(photo, prefix: 'perfil'),
      });
      final response = await _dio.post(
        '/api/v1/employees/$uuid/photo',
        data: formData,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. PRODUCTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchProducts({
    int page = 1,
    int perPage = 20,
    String? branchId,
  }) async {
    try {
      final params = <String, dynamic>{'page': page, 'per_page': perPage};
      final bid = branchId ?? currentBranchId;
      if (bid != null && bid.isNotEmpty) params['branch_id'] = bid;
      final response =
          await _dio.get('/api/v1/products', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Lookup a product by barcode across the entire tenant (no branch filter).
  /// Returns null if not found (404).
  Future<Map<String, dynamic>?> lookupProductByBarcode(String code) async {
    try {
      final response = await _dio
          .get('/api/v1/products/by-barcode', queryParameters: {'code': code});
      return _extractData(response);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw AppError.fromDioException(e);
    }
  }

  // Spec 029: createProduct / updateProduct aceptan opcionalmente
  // `price_tier_1`, `price_tier_2`, `price_tier_3` (números > 0). El
  // backend valida; este lado pasa el payload tal cual.
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> data) async {
    try {
      // Spec 014: defense-in-depth — inject the active sede into the
      // payload so a product is never created with branch_id NULL, the
      // same pattern createSale already follows. The backend resolves
      // the tenant's default sede as the source of truth; this only
      // covers the case where the JWT carries no branch claim. We don't
      // overwrite an explicit branch_id set by the caller.
      final payload = Map<String, dynamic>.from(data);
      final bid = currentBranchId;
      if (bid != null &&
          bid.isNotEmpty &&
          (payload['branch_id'] == null || payload['branch_id'] == '')) {
        payload['branch_id'] = bid;
      }
      final response = await _dio.post('/api/v1/products', data: payload);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateProduct(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/products/$id', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> restockProduct(
      String id, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/products/$id/restock', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _dio.delete('/api/v1/products/$id');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> lookupBarcode(String barcode) async {
    try {
      final response = await _dio.get('/api/v1/products/lookup',
          queryParameters: {'barcode': barcode});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> searchCatalog(String query) async {
    try {
      final response = await _dio
          .get('/api/v1/catalog/search', queryParameters: {'q': query});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> searchProductsOFF(String query) async {
    try {
      final response = await _dio
          .get('/api/v1/products/search-off', queryParameters: {'q': query});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Download the full OFF catalog for offline-first sync.
  Future<List<Map<String, dynamic>>> fetchCatalogSync() async {
    try {
      final response = await _dio.get('/api/v1/products/catalog-sync');
      final data = response.data as Map<String, dynamic>;
      return (data['data'] as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchPendingPrices({
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get('/api/v1/products/pending-prices',
          queryParameters: {'page': page, 'per_page': perPage});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> setProductPrice(
      String uuid, double price) async {
    try {
      final response = await _dio
          .patch('/api/v1/products/$uuid/price', data: {'price': price});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Uploads a payment-receipt photo to the Supabase Storage bucket
  /// `payment_receipts`. Bypasses the VendIA backend on purpose — the
  /// bucket has an 8-day TTL via pg_cron + a 5MB file size cap +
  /// MIME-type allowlist, so the cashier-facing path stays fast and
  /// the backend never touches multipart bytes.
  ///
  /// Returns the public URL of the stored object. The Sale or
  /// CreditPayment row keeps that URL as audit trail even after the
  /// blob itself is purged at day 8.
  Future<String> uploadReceipt(File image) async {
    final ext = image.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}.$ext';
    // Random subdir keeps Supabase listing tidy without leaking any
    // tenant identifier into the URL — the URL becomes evidence even
    // if the blob is gone.
    final path = 'public/$fileName';
    final url = '$supabaseUrl/storage/v1/object/$supabaseReceiptsBucket/$path';

    final dio = Dio();
    try {
      final res = await dio.post<dynamic>(
        url,
        data: image.openRead(),
        options: Options(
          headers: {
            'apikey': supabaseAnonKey,
            'Authorization': 'Bearer $supabaseAnonKey',
            'Content-Type': mime,
            'x-upsert': 'false',
            Headers.contentLengthHeader: await image.length(),
          },
          // Supabase responds 200/201 on success; treat anything else
          // as failure so the picker shows an error and the cashier
          // re-tries instead of submitting a sale with a stale URL.
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      if (res.statusCode == null) {
        throw const AppError(
          type: AppErrorType.network,
          message: 'Sin respuesta de Supabase',
        );
      }
      return '$supabaseUrl/storage/v1/object/public/$supabaseReceiptsBucket/$path';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Uploads a merchant-picked photo for product [uuid].
  ///
  /// Spec 013 / D2: takes an [XFile] (not a `dart:io File`) and reads its
  /// BYTES, so it works on Flutter web — where there is no filesystem and
  /// `XFile.path` is only a blob URL. Spec 013 / D3: the image is first
  /// normalized to a downsized **PNG** via [normalizeImageForUpload]
  /// (the browser decodes HEIC on web; `package:image` re-encodes on
  /// mobile), so an iPhone HEIC photo also renders on Android. This is the
  /// same path `logoMultipart` uses for the store logo.
  ///
  /// Throws [ImageNormalizationException] (Spanish message) when the
  /// picked image cannot be decoded; callers surface it to the merchant.
  Future<Map<String, dynamic>> uploadProductPhoto(
      String uuid, XFile photo) async {
    try {
      final formData = FormData.fromMap({
        'photo': await _imageMultipart(photo, prefix: 'foto'),
      });
      final response =
          await _dio.post('/api/v1/products/$uuid/photo', data: formData);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // Spec 016 / D3: AI photo ops are async. The POST kicks off a backend
  // job and returns a job_id immediately (202); the result arrives later
  // via polling. These tune that loop:
  //  - poll every ~4s (slow enough to be light on Render free, fast
  //    enough that a ~30s job feels responsive),
  //  - give up after ~3 min so a stuck job never blocks the tendero
  //    forever (the backend itself also reaps jobs >5 min — FR-06).
  static const Duration _defaultAiPollInterval = Duration(seconds: 4);
  static const Duration _defaultAiPollTimeout = Duration(minutes: 3);

  // Test seam (Spec 016): instance overrides so the polling loop can be
  // exercised in milliseconds instead of minutes. Production never sets
  // these, so the defaults above apply.
  Duration? _aiPollIntervalOverride;
  Duration? _aiPollTimeoutOverride;

  Duration get _aiPollInterval =>
      _aiPollIntervalOverride ?? _defaultAiPollInterval;
  Duration get _aiPollTimeout =>
      _aiPollTimeoutOverride ?? _defaultAiPollTimeout;

  /// Test seam (Spec 016): shrinks the poll interval / total budget so a
  /// scripted adapter can drive the polling loop without real waits.
  /// Production code never calls this.
  @visibleForTesting
  void setAiPollTimingForTesting({Duration? interval, Duration? timeout}) {
    _aiPollIntervalOverride = interval;
    _aiPollTimeoutOverride = timeout;
  }

  /// Spec 016 / FR-03..FR-05: kicks off a backend AI photo job and polls
  /// its status until it finishes.
  ///
  /// Each HTTP call here — the POST that starts the job and every status
  /// GET — is short, so they keep normal timeouts; the long wait is the
  /// poll loop, not a single blocked request (that was the fragile F015
  /// model this replaces).
  ///
  /// Returns the job result map (`{photo_url: ...}`) on `done` so callers
  /// that `await enhanceProductPhoto(...)` barely change. Throws
  /// [AppError] with a Spanish message when the job reports `failed` or
  /// when the ~3 min poll budget is exhausted — never a raw timeout.
  Future<Map<String, dynamic>> _runAiPhotoJob(
    String uuid,
    String startPath,
    Map<String, String> params,
  ) async {
    try {
      final startResponse = await _dio.post(
        '/api/v1/products/$uuid$startPath',
        queryParameters: params.isEmpty ? null : params,
      );
      final startData = _extractData(startResponse);
      final jobId = startData['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        throw const AppError(
          type: AppErrorType.server,
          message: 'No pudimos iniciar el procesamiento con IA. '
              'Intenta de nuevo.',
        );
      }
      return await _pollAiJob(uuid, jobId);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Polls `GET /products/{id}/ai-job/{jobId}` every [_aiPollInterval]
  /// until the status is `done` (returns the result) or `failed` (throws
  /// the backend's Spanish reason). Stops after [_aiPollTimeout] and
  /// throws a clear Spanish message so the tendero never sees a frozen
  /// screen or a technical timeout (Spec 016 / FR-05).
  Future<Map<String, dynamic>> _pollAiJob(String uuid, String jobId) async {
    final deadline = DateTime.now().add(_aiPollTimeout);
    while (true) {
      Map<String, dynamic> job;
      try {
        final response = await _dio.get('/api/v1/products/$uuid/ai-job/$jobId');
        job = _extractData(response);
      } on DioException catch (e) {
        throw AppError.fromDioException(e);
      }

      final status = job['status'] as String?;
      if (status == 'done') {
        return job;
      }
      if (status == 'failed') {
        final reason = job['error'] as String?;
        throw AppError(
          type: AppErrorType.server,
          message: (reason != null && reason.isNotEmpty)
              ? reason
              : 'No pudimos procesar la foto con IA. Intenta de nuevo.',
        );
      }

      // status == 'processing' (or anything unknown) → keep waiting,
      // unless we have run out of the poll budget.
      if (!DateTime.now().add(_aiPollInterval).isBefore(deadline)) {
        throw const AppError(
          type: AppErrorType.network,
          message: 'La IA está tardando más de lo normal. '
              'Intenta de nuevo en un momento.',
        );
      }
      await Future<void>.delayed(_aiPollInterval);
    }
  }

  Future<Map<String, dynamic>> enhanceProductPhoto(
    String uuid, {
    String? name,
    String? presentation,
    String? content,
  }) async {
    final params = <String, String>{};
    if (name != null && name.isNotEmpty) params['name'] = name;
    if (presentation != null && presentation.isNotEmpty) {
      params['presentation'] = presentation;
    }
    if (content != null && content.isNotEmpty) params['content'] = content;
    // Spec 016: POST returns 202 with a job_id; _runAiPhotoJob then polls
    // for the result, so callers keep their plain `await` + loader.
    return _runAiPhotoJob(uuid, '/enhance', params);
  }

  /// Spec 043: genera una descripción corta y apetecible para un plato del
  /// menú a partir de su nombre (+ categoría). Síncrono (texto). Devuelve la
  /// descripción lista para precargar en el editor (el tendero la edita).
  Future<String> generateMenuDescription({
    required String name,
    String category = '',
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/menu/generate-description',
        data: {'name': name, if (category.isNotEmpty) 'category': category},
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      final data = _extractData(response);
      return (data['description'] as String?)?.trim() ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 043 (concilio opción C): genera una foto de MUESTRA del plato con
  /// IA y devuelve la URL en R2 (sin crear producto). La muestra se basa en
  /// nombre + descripción (ingredientes) + presentación (cómo se sirve) para
  /// que sea mucho más certera. El editor la guarda en el plato y la incluye
  /// en createProduct al publicar. Síncrono; timeout amplio como el escaneo.
  Future<String> generateMenuImage({
    required String name,
    String category = '',
    String description = '',
    String presentation = '',
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/menu/generate-image',
        data: {
          'name': name,
          if (category.isNotEmpty) 'category': category,
          if (description.isNotEmpty) 'description': description,
          if (presentation.isNotEmpty) 'presentation': presentation,
        },
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      final data = _extractData(response);
      return (data['image_url'] as String?)?.trim() ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 043: mejora FIEL de la foto REAL del plato (subida por el tendero).
  /// Recorta el fondo + luz de estudio sin redibujar el plato (Spec 017,
  /// EnhancePhoto) — el comensal ve el plato real, solo mejor fotografiado.
  /// Espejo de [scanMenuPhoto]: viaja como BYTES + [MultipartFile.fromBytes]
  /// para funcionar también en Flutter web (sin `dart:io File`/`XFile.path`).
  /// Devuelve la URL de la foto mejorada en R2.
  Future<String> enhanceMenuImage({
    required Uint8List imageBytes,
    required String name,
    String category = '',
    String mimeType = 'image/jpeg',
    String filename = 'plato.jpg',
  }) async {
    try {
      final formData = FormData.fromMap({
        'name': name,
        if (category.isNotEmpty) 'category': category,
        'image': MultipartFile.fromBytes(
          imageBytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final response = await _dio.post(
        '/api/v1/menu/enhance-image',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      final data = _extractData(response);
      return (data['image_url'] as String?)?.trim() ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> generateProductImage(
    String uuid, {
    String? name,
    String? presentation,
    String? content,
    String? barcode,
  }) async {
    final params = <String, String>{};
    if (name != null && name.isNotEmpty) params['name'] = name;
    if (presentation != null && presentation.isNotEmpty) {
      params['presentation'] = presentation;
    }
    if (content != null && content.isNotEmpty) params['content'] = content;
    if (barcode != null && barcode.isNotEmpty) params['barcode'] = barcode;
    // Spec 016: same async POST + polling flow as enhanceProductPhoto.
    return _runAiPhotoJob(uuid, '/generate-image', params);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. INVENTORY IA
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> scanInvoice(File image) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(image.path),
      });
      final response = await _dio.post('/api/v1/inventory/scan-invoice',
          data: formData,
          options: Options(receiveTimeout: const Duration(seconds: 30)));
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 043 (menú restaurante): envía una foto de la CARTA/MENÚ a Gemini y
  /// recibe los platos extraídos `[{name, description, price, portion,
  /// category}]` para que el tendero los revise/edite antes de publicarlos.
  /// Igual que [voiceInventory], viaja como BYTES + [MultipartFile.fromBytes]
  /// para que funcione también en Flutter web (sin `dart:io File`/`XFile.path`).
  Future<List<Map<String, dynamic>>> scanMenuPhoto({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    String filename = 'menu.jpg',
  }) async {
    try {
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(
          imageBytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final response = await _dio.post('/api/v1/menu/scan-photo',
          data: formData,
          options: Options(receiveTimeout: const Duration(seconds: 45)));
      final data = _extractData(response);
      final dishes = (data['dishes'] as List?) ?? const [];
      return dishes
          .whereType<Map>()
          .map((d) => Map<String, dynamic>.from(d))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 045 — onboarding agéntico. Manda el texto escrito/dictado (y opcional
  /// una nota de voz) + el estado ya capturado (`current`) al endpoint PÚBLICO
  /// POST /api/v1/auth/onboarding-parse y devuelve el mapa
  /// `{fields, confidence, needs_confirmation, clarify_prompt, degraded, reason}`.
  ///
  /// La IA es un acelerador OPCIONAL: ante cualquier fallo se devuelve un mapa
  /// `degraded:true` (nunca lanza) para que el onboarding caiga a edición manual
  /// sin bloquear el registro. Web-safe: el audio viaja como BYTES
  /// (MultipartFile.fromBytes), nunca dart:io File ni XFile.path.
  Future<Map<String, dynamic>> parseOnboarding({
    String text = '',
    Uint8List? audioBytes,
    String mimeType = 'audio/webm',
    String filename = 'onboarding.webm',
    Map<String, dynamic>? current,
  }) async {
    try {
      final form = <String, dynamic>{
        if (text.isNotEmpty) 'text': text,
        if (current != null && current.isNotEmpty) 'current': jsonEncode(current),
        if (audioBytes != null)
          'audio': MultipartFile.fromBytes(
            audioBytes,
            filename: filename,
            contentType: DioMediaType.parse(mimeType),
          ),
      };
      final response = await _dio.post(
        '/api/v1/auth/onboarding-parse',
        data: FormData.fromMap(form),
        options: Options(receiveTimeout: const Duration(seconds: 50)),
      );
      final data = _extractData(response);
      return Map<String, dynamic>.from(data);
    } catch (_) {
      // Degradación elegante: la IA nunca bloquea el registro (Art. I + II).
      return {
        'fields': <String, dynamic>{},
        'needs_confirmation': <String>[],
        'degraded': true,
        'reason': 'network',
      };
    }
  }

  /// Phase-4 Voice-to-Catalog: ships the tendero's recorded note to
  /// Gemini multimodal and returns the parsed `[{name, quantity,
  /// price}]` array. The backend gates the endpoint behind
  /// PremiumAuth — an expired trial returns 403 premium_expired and
  /// bubbles up through the existing soft-paywall interceptor.
  ///
  /// Spec 020: the audio arrives as raw BYTES (not a `dart:io File`) and
  /// the multipart part is built with `MultipartFile.fromBytes`, so the
  /// upload works on Flutter web too — where the browser hands back a
  /// blob, not a filesystem path. [mimeType] is the real codec
  /// (`audio/m4a` on mobile, `audio/webm` on web) and [filename] carries
  /// the matching extension so the backend's sniffing has a hint.
  Future<List<Map<String, dynamic>>> voiceInventory({
    required Uint8List audioBytes,
    required String mimeType,
    String filename = 'vendia_voice',
  }) async {
    try {
      final fields = <String, dynamic>{
        'audio_file': MultipartFile.fromBytes(
          audioBytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      };
      // Phase-6: forward the active sede so the handler can tag any
      // future DB writes with the right branch_id. The current
      // handler only extracts from audio, but the contract is in
      // place for when "guardar desde voz" wires through.
      if (currentBranchId != null && currentBranchId!.isNotEmpty) {
        fields['branch_id'] = currentBranchId!;
      }
      final formData = FormData.fromMap(fields);
      final response = await _dio.post(
        '/api/v1/ai/voice-inventory',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 065 — Recipe Studio: dicta una receta por voz. Envía el audio
  /// (BYTES, web-safe) a `/ai/voice-recipe` y devuelve la receta estructurada
  /// `{name, description, yield, prep_time, ingredients:[{name,quantity,unit}],
  /// steps:[...]}` para precargar el Studio. El usuario siempre revisa/edita.
  Future<Map<String, dynamic>> voiceRecipe({
    required Uint8List audioBytes,
    required String mimeType,
    String filename = 'vendia_recipe_voice',
  }) async {
    try {
      final formData = FormData.fromMap({
        'audio_file': MultipartFile.fromBytes(
          audioBytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final response = await _dio.post(
        '/api/v1/ai/voice-recipe',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 065 — Asistente IA de recetas (texto): completa o refina. Manda el
  /// nombre, el borrador actual y opcionalmente instrucciones libres
  /// ("hazla más económica", "para 10 porciones") y devuelve la receta
  /// refinada en el mismo formato que [voiceRecipe].
  Future<Map<String, dynamic>> recipeAssist({
    required String name,
    String instructions = '',
    Map<String, dynamic>? current,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/ai/recipe-assist',
        data: {
          'name': name,
          if (instructions.isNotEmpty) 'instructions': instructions,
          if (current != null) 'current': current,
        },
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchInventoryAlerts() async {
    try {
      final response =
          await _dio.get('/api/v1/inventory/alerts', queryParameters: {
        if (currentBranchId != null && currentBranchId!.isNotEmpty)
          'branch_id': currentBranchId,
      });
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> logInvoiceSave(Map<String, dynamic> data) async {
    try {
      await _dio.post('/api/v1/inventory/invoice-logs', data: data);
    } on DioException catch (_) {
      // Best-effort — don't block the save flow
    }
  }

  Future<Map<String, dynamic>> fetchInvoiceLogs({
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response =
          await _dio.get('/api/v1/inventory/invoice-logs', queryParameters: {
        'page': page,
        'per_page': perPage,
        if (currentBranchId != null && currentBranchId!.isNotEmpty)
          'branch_id': currentBranchId,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchReorderSuggestions() async {
    try {
      final response = await _dio
          .get('/api/v1/inventory/reorder-suggestions', queryParameters: {
        if (currentBranchId != null && currentBranchId!.isNotEmpty)
          'branch_id': currentBranchId,
      });
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchExpiringProducts() async {
    try {
      final response = await _dio.get('/api/v1/inventory/expiring');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ── Kardex & Inventory Report ──

  Future<Map<String, dynamic>> fetchProductKardex(
    String productId, {
    int page = 1,
    int perPage = 30,
  }) async {
    try {
      final response =
          await _dio.get('/api/v1/inventory/kardex', queryParameters: {
        'product_id': productId,
        'page': page,
        'per_page': perPage,
        if (currentBranchId != null && currentBranchId!.isNotEmpty)
          'branch_id': currentBranchId,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchInventoryReport({
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final response =
          await _dio.get('/api/v1/inventory/report', queryParameters: {
        'page': page,
        'per_page': perPage,
        if (currentBranchId != null && currentBranchId!.isNotEmpty)
          'branch_id': currentBranchId,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<List<Map<String, dynamic>>>> matchProducts(
    List<Map<String, dynamic>> products,
  ) async {
    try {
      final response =
          await _dio.post('/api/v1/inventory/match-products', data: {
        'products': products,
      });
      final raw = response.data['data'] as List;
      return raw.map<List<Map<String, dynamic>>>((list) {
        if (list == null) return [];
        return (list as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      }).toList();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. SALES (POS)
  // ═══════════════════════════════════════════════════════════════════════════

  // Spec 029: createSale acepta opcionalmente `price_tier`
  // (uno de 'retail' | 'tier_1' | 'tier_2' | 'tier_3'). Default
  // server-side: 'retail'.
  Future<Map<String, dynamic>> createSale(Map<String, dynamic> data) async {
    try {
      // Phase-6 isolation: the backend scopes stock decrement to
      // the sede in the payload. We inject currentBranchId only
      // when the caller didn't already set it, so explicit payloads
      // (e.g. the register "Sede Principal" bootstrap) keep priority.
      final payload = Map<String, dynamic>.from(data);
      final bid = currentBranchId;
      if (bid != null &&
          bid.isNotEmpty &&
          (payload['branch_id'] == null || payload['branch_id'] == '')) {
        payload['branch_id'] = bid;
      }
      final response = await _dio.post('/api/v1/sales', data: payload);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchSales({
    int page = 1,
    int perPage = 20,
    String? branchId,
  }) async {
    try {
      final params = <String, dynamic>{'page': page, 'per_page': perPage};
      final bid = branchId ?? currentBranchId;
      if (bid != null && bid.isNotEmpty) params['branch_id'] = bid;
      final response = await _dio.get('/api/v1/sales', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchSalesToday() async {
    try {
      final response = await _dio.get('/api/v1/sales/today');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchSalesHistory({
    String? date,
    String? startDate,
    String? endDate,
    String? source,
    String? paymentMethod,
    String? query,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final params = _branchParams({
        'page': page,
        'per_page': perPage,
      });
      if (date != null) params['date'] = date;
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      if (source != null) params['source'] = source;
      if (paymentMethod != null) params['payment_method'] = paymentMethod;
      if (query != null) params['query'] = query;
      final response =
          await _dio.get('/api/v1/sales/history', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchReceipt(String uuid) async {
    try {
      final response = await _dio.get('/api/v1/sales/$uuid/receipt');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> reprintReceipt(String uuid) async {
    try {
      final response = await _dio.post('/api/v1/sales/$uuid/reprint');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> sendReceiptWhatsApp(String uuid) async {
    try {
      final response = await _dio.post('/api/v1/sales/$uuid/send-receipt');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. CUSTOMERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchCustomers({
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get('/api/v1/customers',
          queryParameters: {'page': page, 'per_page': perPage});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/customers', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateCustomer(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/customers/$id', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // F030 — administración de clientes y ventas.
  //
  // [listCustomers] alimenta la pantalla "Mis clientes": lista paginada
  // con búsqueda por nombre/teléfono. Cada item incluye los agregados
  // (`total_spent`, `purchase_count`, `last_purchase_at`) calculados
  // server-side con JOIN a `sales`.
  //
  // Devuelve el cuerpo crudo `{ data: [...], meta: {...} }` para que la
  // pantalla pueda leer tanto la lista como la paginación.

  /// Lista clientes del tenant con sus agregados de compra.
  ///
  /// [query]  → texto de búsqueda por nombre o teléfono (param `q`).
  /// [limit]  → tamaño de página (default 50, el backend topa en 200).
  /// [offset] → desplazamiento para paginación.
  Future<Map<String, dynamic>> listCustomers({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final params = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };
      final q = query?.trim();
      if (q != null && q.isNotEmpty) params['q'] = q;
      final response =
          await _dio.get('/api/v1/customers', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ── Eventos (F042) ───────────────────────────────────────────────

  /// Lista los eventos del tenant. `status` opcional filtra por estado.
  /// Spec: specs/042-modulo-eventos/spec.md
  Future<List<Map<String, dynamic>>> listEvents({String? status}) async {
    try {
      final params = <String, dynamic>{};
      if (status != null && status.isNotEmpty) params['status'] = status;
      final response =
          await _dio.get('/api/v1/events', queryParameters: params);
      final data = (response.data as Map<String, dynamic>)['data'] as List?;
      return (data ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea un evento. Devuelve el registro creado (`data`).
  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/api/v1/events', data: body);
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Tasa de cambio USD→COP (cuántos COP vale 1 USD) para convertir el precio
  /// del evento al cambiar de moneda. Devuelve 0 si no se pudo obtener.
  Future<double> fetchUsdCopRate() async {
    try {
      final response = await _dio.get('/api/v1/fx/usd-cop');
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['cop_per_usd'] as num? ?? 0).toDouble();
    } on DioException {
      return 0;
    }
  }

  /// Actualiza campos de un evento (PATCH parcial). Ej: la descripción
  /// pública que verán los clientes en el catálogo (F042).
  Future<Map<String, dynamic>> updateEvent(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await _dio.patch('/api/v1/events/$id', data: body);
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Publica un evento (borrador → publicado).
  Future<Map<String, dynamic>> publishEvent(String id) async {
    try {
      final response = await _dio.post('/api/v1/events/$id/publish');
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Registra un abono (cuota o pago total) de un inscrito. Al completar el
  /// precio, el backend confirma la inscripción y activa el carné (F042).
  Future<Map<String, dynamic>> recordEventPayment(
      String eventId, String regId, int amount) async {
    try {
      final response = await _dio.post(
        '/api/v1/events/$eventId/registrations/$regId/payments',
        data: {'amount': amount},
      );
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Asigna, mueve o libera la silla de un asistente (mapa de sillas, F042).
  /// `seat` null libera la silla; un número la asigna/mueve.
  Future<Map<String, dynamic>> assignEventSeat(
      String eventId, String regId, int? seat) async {
    try {
      final response = await _dio.put(
        '/api/v1/events/$eventId/registrations/$regId/seat',
        data: {'seat_number': seat},
      );
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Marca la inscripción como pagada en su totalidad (carné activado).
  Future<Map<String, dynamic>> confirmEventPayment(
      String eventId, String regId) async {
    try {
      final response = await _dio.post(
        '/api/v1/events/$eventId/registrations/$regId/confirm-payment',
      );
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Lista los comprobantes/pagos de un evento (por defecto los pendientes
  /// de revisión) para la bandeja del organizador (F042).
  Future<List<Map<String, dynamic>>> listEventPayments(String eventId,
      {String status = 'pending'}) async {
    try {
      final response = await _dio.get(
        '/api/v1/events/$eventId/payments',
        queryParameters: {if (status.isNotEmpty) 'status': status},
      );
      final data = (response.data as Map<String, dynamic>)['data'] as List?;
      return (data ?? []).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Aprueba un comprobante: su monto se cuenta y el carné se activa al
  /// completar el precio (F042). Devuelve la inscripción actualizada.
  Future<Map<String, dynamic>> approveEventPayment(
      String eventId, String paymentId) async {
    try {
      final response = await _dio
          .post('/api/v1/events/$eventId/payments/$paymentId/approve');
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Lista los inscritos de un evento (panel del organizador, F042).
  Future<List<Map<String, dynamic>>> listEventRegistrations(
      String eventId) async {
    try {
      final response = await _dio.get('/api/v1/events/$eventId/registrations');
      final data = (response.data as Map<String, dynamic>)['data'] as List?;
      return (data ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Registra un escaneo de entrada/salida (check-in/out) por QR.
  /// Devuelve `already_registered` cuando el QR ya había sido escaneado.
  Future<bool> checkinEvent(
      String eventId, String qrToken, String scanType) async {
    try {
      final response = await _dio.post(
        '/api/v1/events/$eventId/checkin',
        data: {'qr_token': qrToken, 'scan_type': scanType},
      );
      final body = response.data as Map<String, dynamic>;
      return body['already_registered'] == true;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Emite manualmente el certificado de un asistente elegible (F042).
  Future<void> issueEventCertificate(String eventId, String regId) async {
    try {
      await _dio
          .post('/api/v1/events/$eventId/registrations/$regId/certificate');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Envío masivo: emite el certificado a todos los que registraron entrada y
  /// salida (elegibles) y aún no lo tenían. Devuelve cuántos emitió.
  Future<int> issueAllEventCertificates(String eventId) async {
    try {
      final response =
          await _dio.post('/api/v1/events/$eventId/certificates/issue-all');
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['issued'] as num? ?? 0).toInt();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Cuerpo opcional `{brief}` para los generadores con IA: la indicación
  /// libre del organizador ("muestra manos decorando un pastel"). Se omite
  /// cuando está vacío para no enviar un body innecesario.
  Object? _briefBody(String? brief) {
    final b = brief?.trim() ?? '';
    return b.isEmpty ? null : {'brief': b};
  }

  /// Genera el diseño de la ESCARAPELA del evento con IA y devuelve la URL.
  /// El backend persiste la URL en la plantilla del evento (F042 FR-11).
  /// [brief] es la indicación opcional del organizador para guiar a la IA.
  Future<String> generateEventBadge(String eventId, {String? brief}) async {
    try {
      final response = await _dio.post(
        '/api/v1/events/$eventId/badge/ai-generate',
        data: _briefBody(brief),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['image_url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Genera el diseño del CERTIFICADO del evento con IA (F042 FR-12).
  /// [brief] es la indicación opcional del organizador para guiar a la IA.
  Future<String> generateEventCertificate(String eventId, {String? brief}) async {
    try {
      final response = await _dio.post(
        '/api/v1/events/$eventId/certificate/ai-generate',
        data: _briefBody(brief),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['image_url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Genera el AFICHE publicitario del evento con IA — la pieza que se muestra
  /// en el catálogo público (el link que se comparte por WhatsApp). Sin QR.
  /// [brief] es la indicación opcional del organizador para guiar a la IA
  /// (escena, estilo, elementos de la pieza).
  Future<String> generateEventPoster(String eventId, {String? brief}) async {
    try {
      final response = await _dio.post(
        '/api/v1/events/$eventId/poster/ai-generate',
        data: _briefBody(brief),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['image_url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Mejora/transforma con IA la imagen ACTUAL de una pieza del evento
  /// ([asset] = 'poster' | 'badge' | 'certificate'). Si se envía [brief], la IA
  /// RECREA la escena siguiendo esas indicaciones usando la foto como
  /// referencia; sin brief, solo retoca. [faceReference] (opcional) es una foto
  /// clara del rostro para anclar la identidad. Devuelve la nueva URL.
  Future<String> enhanceEventAsset(String eventId, String asset,
      {String? brief, XFile? faceReference}) async {
    try {
      final form = <String, dynamic>{};
      final b = brief?.trim() ?? '';
      if (b.isNotEmpty) form['brief'] = b;
      if (faceReference != null) {
        form['reference'] = await imageMultipart(faceReference, prefix: 'face');
      }
      final response = await _dio.post(
        '/api/v1/events/$eventId/$asset/ai-enhance',
        data: FormData.fromMap(form),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['image_url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Sube la imagen propia del organizador para una pieza del evento
  /// ([asset] = 'poster' | 'badge' | 'certificate') como alternativa a la IA
  /// (F042 FR-11/13). Devuelve la URL persistida en la plantilla del evento.
  /// La imagen se normaliza a PNG (HEIC/web) antes de enviarse.
  Future<String> uploadEventAsset(String eventId, String asset, XFile image) async {
    try {
      final formData = FormData.fromMap({
        'image': await imageMultipart(image, prefix: asset),
      });
      final response =
          await _dio.post('/api/v1/events/$eventId/$asset/upload', data: formData);
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['image_url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Agente IA que redacta la descripción del evento a partir de lo que el
  /// organizador respondió. Devuelve el texto sugerido (markdown ligero).
  Future<String> generateEventDescription({
    required String title,
    String type = '',
    String modality = '',
    String topic = '',
    String audience = '',
    String includes = '',
    String level = '',
    String place = '',
    String extra = '',
    String current = '',
  }) async {
    try {
      final response = await _dio.post('/api/v1/event-description-ai', data: {
        'title': title,
        'type': type,
        'modality': modality,
        'topic': topic,
        'audience': audience,
        'includes': includes,
        'level': level,
        'place': place,
        'extra': extra,
        'current': current,
      });
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['description'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Guarda SOLO la configuración del certificado (texto, firma, logo, layout)
  /// desde el diseñador, sin tocar el resto del evento. Devuelve el evento.
  Future<Map<String, dynamic>> updateEventCertificateConfig(
      String eventId, Map<String, dynamic> config) async {
    try {
      final response = await _dio
          .put('/api/v1/events/$eventId/certificate-config', data: config);
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Guarda el diseño WYSIWYG del CARNÉ/escarapela (layout + textos), espejo de
  /// updateEventCertificateConfig.
  Future<Map<String, dynamic>> updateEventBadgeConfig(
      String eventId, Map<String, dynamic> config) async {
    try {
      final response =
          await _dio.put('/api/v1/events/$eventId/badge-config', data: config);
      return (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Sube una imagen genérica del evento (logo, etc.) y devuelve su URL.
  Future<String> uploadEventImage(XFile image) => uploadEventPaymentQR(image);

  /// Limpia con IA la foto de la firma (aísla los trazos, quita el fondo) y
  /// devuelve la URL de la imagen lista para el certificado.
  Future<String> cleanEventSignature(XFile image) async {
    try {
      final formData = FormData.fromMap({
        'image': await imageMultipart(image, prefix: 'firma'),
      });
      final response = await _dio.post('/api/v1/event-signature-clean',
          data: formData,
          options: Options(receiveTimeout: const Duration(seconds: 70)));
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Redacta con IA los 5 textos del certificado (título, frase, cuerpo,
  /// firmante, nota al pie) a partir de la info del evento. Devuelve un mapa
  /// con esas claves; el organizador puede editarlos después.
  Future<Map<String, String>> generateCertificateTexts({
    required String title,
    required String type,
    required String modality,
    required String description,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/event-certificate-texts-ai',
        data: {
          'title': title,
          'type': type,
          'modality': modality,
          'description': description,
        },
        options: Options(receiveTimeout: const Duration(seconds: 40)),
      );
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, (v ?? '').toString()));
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Quita SOLO el fondo del logo actual (recuadro blanco exterior) sin tocar
  /// los colores ni los blancos internos del diseño, y devuelve la URL del PNG
  /// transparente liviano. Recibe la URL del logo ya cargado (no un archivo).
  Future<String> removeEventLogoBackground(String url) async {
    try {
      final formData = FormData.fromMap({'url': url});
      final response = await _dio.post('/api/v1/event-logo-remove-bg',
          data: formData,
          options: Options(receiveTimeout: const Duration(seconds: 40)));
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Sube la imagen del QR de un medio de pago y devuelve su URL, para
  /// incluirla en payment_details al guardar el evento (sirve al crear y
  /// editar — no requiere id del evento).
  Future<String> uploadEventPaymentQR(XFile image) async {
    try {
      final formData = FormData.fromMap({
        'image': await imageMultipart(image, prefix: 'payqr'),
      });
      final response =
          await _dio.post('/api/v1/event-payment-qr', data: formData);
      final data = (response.data as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      return (data['url'] as String?) ?? '';
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Historial de compras de un cliente: registro base + summary
  /// (gastado, compras, primera/última visita) + lista de ventas.
  ///
  /// Devuelve el contenido de la clave `data` de
  /// GET /api/v1/customers/:id/history.
  Future<Map<String, dynamic>> getCustomerHistory(String id) async {
    try {
      final response = await _dio.get('/api/v1/customers/$id/history');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7b. QUOTES (Cotizaciones — F031)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // CRUD + acciones del módulo de cotizaciones. Contrato en
  // specs/031-cotizaciones/plan.md §4. Endpoints privados bajo JWT.

  /// Lista cotizaciones del tenant con filtros opcionales.
  ///
  /// [status] → filtro por estado (wire de QuoteStatus, ej. 'enviada').
  /// [query]  → texto de búsqueda por folio o nombre de cliente.
  ///
  /// Devuelve el cuerpo crudo `{ data: [...], meta: {...} }`.
  Future<Map<String, dynamic>> listQuotes({
    String? status,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final params = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };
      if (status != null && status.isNotEmpty) params['status'] = status;
      final q = query?.trim();
      if (q != null && q.isNotEmpty) params['q'] = q;
      final response =
          await _dio.get('/api/v1/quotes', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea una cotización en estado `borrador`. El backend asigna el
  /// folio secuencial y calcula los totales. Devuelve la cotización
  /// creada (clave `data`).
  Future<Map<String, dynamic>> createQuote(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/quotes', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Detalle completo de una cotización (items + cliente).
  Future<Map<String, dynamic>> getQuote(String id) async {
    try {
      final response = await _dio.get('/api/v1/quotes/$id');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Edita una cotización. Si está en `borrador` se sobrescribe; si
  /// está `enviada` el backend crea la V2 y marca la v1 `reemplazada`.
  /// Devuelve la cotización resultante (la V2 cuando aplica).
  Future<Map<String, dynamic>> updateQuote(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/quotes/$id', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Marca una cotización `borrador` como `enviada` y le asigna
  /// `sent_at`. No envía nada por sí mismo — el cliente arma el
  /// link/mensaje con el `public_token` del response.
  Future<Map<String, dynamic>> sendQuote(String id) async {
    try {
      final response = await _dio.post('/api/v1/quotes/$id/send');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Convierte una cotización `aprobada` en venta: crea la venta con
  /// los mismos items, descuenta inventario y devuelve `sale_id`. La
  /// cotización pasa a `convertida`.
  Future<Map<String, dynamic>> convertQuote(String id) async {
    try {
      final response = await _dio.post('/api/v1/quotes/$id/convert');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Marca manualmente el estado de una cotización (aprobación verbal).
  /// [status] es el wire de QuoteStatus — `aprobada` o `rechazada`.
  Future<Map<String, dynamic>> markQuoteStatus(
    String id,
    String status, {
    String? note,
  }) async {
    try {
      final body = <String, dynamic>{'status': status};
      if (note != null && note.isNotEmpty) body['note'] = note;
      final response =
          await _dio.post('/api/v1/quotes/$id/mark-status', data: body);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. CREDITS (El Fiar)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchCredits({
    String? status,
    int page = 1,
    int perPage = 20,
    String? branchId,
  }) async {
    try {
      final bid = branchId ?? currentBranchId;
      final params = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (status != null) params['status'] = status;
      if (bid != null && bid.isNotEmpty) params['branch_id'] = bid;
      final response =
          await _dio.get('/api/v1/credits', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Returns one row per CUSTOMER for the "Activos" tab of the cuaderno.
  /// Backend aggregates every open/partial/pending credit_account belonging
  /// to a customer into a single record so the UI never duplicates a
  /// person's name even if data inconsistencies leak two ledger rows.
  /// Each entry exposes:
  ///   customer_id, customer_name, customer_phone, total_amount,
  ///   paid_amount, balance, accounts_count, latest_activity_at, status.
  Future<List<Map<String, dynamic>>> fetchCreditsGroupedByCustomer({
    String? branchId,
  }) async {
    try {
      final bid = branchId ?? currentBranchId;
      final params = <String, dynamic>{'group_by': 'customer'};
      if (bid != null && bid.isNotEmpty) params['branch_id'] = bid;
      final response =
          await _dio.get('/api/v1/credits', queryParameters: params);
      final data = (response.data as Map<String, dynamic>)['data'];
      if (data is List) return data.cast<Map<String, dynamic>>();
      return const [];
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> recordCreditPayment(
      String creditId, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/credits/$creditId/payments', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> remindDebt(String customerUuid) async {
    try {
      final response = await _dio.post('/api/v1/fiar/remind/$customerUuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. ORDERS / KDS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/orders', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchOrders({String? status}) async {
    try {
      final params = <String, dynamic>{};
      if (status != null) params['status'] = status;
      final response =
          await _dio.get('/api/v1/orders', queryParameters: params);
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchOrder(String uuid) async {
    try {
      final response = await _dio.get('/api/v1/orders/$uuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateOrderStatus(String uuid, String status,
      {String? paymentMethod}) async {
    try {
      final data = <String, dynamic>{'status': status};
      if (paymentMethod != null) data['payment_method'] = paymentMethod;
      final response =
          await _dio.patch('/api/v1/orders/$uuid/status', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchOpenAccounts() async {
    try {
      final response = await _dio.get('/api/v1/orders/open-accounts');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Finds the most recently opened ticket whose `label` matches
  /// [tableLabel] (case-insensitive, trimmed) and returns the row
  /// verbatim — the caller reads `session_token` from it to build
  /// the live-tab URL for the QR.
  ///
  /// Returns `null` when no open ticket exists for that table. We
  /// deliberately do NOT create a ticket here: the QR is only
  /// meaningful once the first item has been added to the tab,
  /// and auto-creating an empty ticket would pollute the KDS.
  Future<Map<String, dynamic>?> fetchOpenTicketByLabel(
    String tableLabel,
  ) async {
    final wanted = tableLabel.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    final accounts = await fetchOpenAccounts();
    Map<String, dynamic>? best;
    DateTime? bestCreated;
    for (final row in accounts) {
      final label = (row['label'] as String?)?.trim().toLowerCase() ?? '';
      if (label != wanted) continue;
      final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
      // Newest wins — the KDS lists ASC, but if a historical open
      // ticket lingers we still want the freshest one.
      if (bestCreated == null ||
          (created != null && created.isAfter(bestCreated))) {
        best = row;
        bestCreated = created;
      }
    }
    return best;
  }

  /// Persists (upserts) the local cart for a table as an OPEN
  /// OrderTicket on the backend, keyed by `label`. Returns the
  /// response `data` object, which always contains:
  ///   - session_token   (UUID, stable across upserts)
  ///   - order_id        (ticket UUID)
  ///   - total           (re-computed server-side)
  ///
  /// This is the source of truth for the live-tab QR: persist
  /// first, then store the returned token in the local
  /// [AccountContext] so the QR sheet can render without
  /// round-tripping through /orders/open-accounts every time.
  Future<Map<String, dynamic>> upsertTableTab({
    required String label,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? employeeUuid,
    String? employeeName,
  }) async {
    try {
      final response = await _dio.put('/api/v1/tables/tab', data: {
        'label': label,
        'items': items,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
        if (employeeUuid != null && employeeUuid.isNotEmpty)
          'employee_uuid': employeeUuid,
        if (employeeName != null && employeeName.isNotEmpty)
          'employee_name': employeeName,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Adds items to an existing table tab (accumulate-only, never removes).
  /// Creates the tab if none exists. Returns the updated tab data.
  Future<Map<String, dynamic>> addItemsToTableTab({
    required String label,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? employeeName,
  }) async {
    try {
      final response = await _dio.post('/api/v1/tables/tab/add-items', data: {
        'label': label,
        'items': items,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
        if (employeeName != null && employeeName.isNotEmpty)
          'employee_name': employeeName,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Removes a single item from an open table tab. Restores stock.
  Future<Map<String, dynamic>> removeItemFromTab(
      String orderUuid, String itemId) async {
    try {
      final response =
          await _dio.delete('/api/v1/orders/$orderUuid/items/$itemId');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Authenticated lookup that mirrors UpsertTableTab but without
  /// mutating anything. Used by the QR sheet as a fallback when
  /// the local context has no session_token yet — e.g. the cashier
  /// opened the tab on another device.
  Future<Map<String, dynamic>?> fetchTableTabByLabel(String label) async {
    final clean = label.trim();
    if (clean.isEmpty) return null;
    try {
      final response = await _dio.get(
        '/api/v1/tables/tab/${Uri.encodeComponent(clean)}',
      );
      return _extractData(response);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> closeOrder(
      String uuid, String paymentMethod) async {
    try {
      final response = await _dio.post('/api/v1/orders/$uuid/close',
          data: {'payment_method': paymentMethod});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. SUPPLIERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchSuppliers() async {
    try {
      final response = await _dio.get('/api/v1/suppliers');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/suppliers', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateSupplier(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/suppliers/$uuid', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deleteSupplier(String uuid) async {
    try {
      await _dio.delete('/api/v1/suppliers/$uuid');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> orderViaWhatsApp(
      String supplierUuid, Map<String, dynamic> data) async {
    try {
      final response = await _dio
          .post('/api/v1/suppliers/$supplierUuid/order-wa', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. RECIPES / INSUMOS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchRecipes() async {
    try {
      final response = await _dio.get('/api/v1/recipes');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createRecipe(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/recipes', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Spec 065 — edita una receta existente (PATCH /recipes/:uuid). Acepta los
  /// mismos campos que createRecipe (incluidos prep_steps/yield/prep_time y,
  /// opcionalmente, el set de `ingredients` a reemplazar).
  Future<Map<String, dynamic>> updateRecipe(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/recipes/$uuid', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchRecipeCost(String uuid) async {
    try {
      final response = await _dio.get('/api/v1/recipes/$uuid/cost');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// DELETE /api/v1/recipes/:uuid — borra una receta. El backend ya lo expone;
  /// faltaba el método cliente para la lista "Ver mis recetas".
  Future<void> deleteRecipe(String uuid) async {
    try {
      await _dio.delete('/api/v1/recipes/$uuid');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ── Insumos (Feature 001) — contrato en plan.md §4 ────────────────────────

  /// Lista los insumos del tenant. GET /api/v1/ingredients.
  Future<List<Map<String, dynamic>>> fetchIngredients() async {
    try {
      final response = await _dio.get('/api/v1/ingredients');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea un insumo. POST /api/v1/ingredients.
  Future<Map<String, dynamic>> createIngredient(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/ingredients', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Actualiza campos parciales de un insumo. PATCH /api/v1/ingredients/:uuid.
  /// El stock NO se ajusta por aquí — eso pasa por kardex (plan.md §4).
  Future<Map<String, dynamic>> updateIngredient(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.patch('/api/v1/ingredients/$uuid', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Elimina (soft delete) un insumo. DELETE /api/v1/ingredients/:uuid.
  Future<void> deleteIngredient(String uuid) async {
    try {
      await _dio.delete('/api/v1/ingredients/$uuid');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Insumos bajo su stock mínimo. GET /api/v1/ingredients/low-stock (AC-05).
  Future<List<Map<String, dynamic>>> fetchLowStockIngredients() async {
    try {
      final response = await _dio.get('/api/v1/ingredients/low-stock');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Disponibilidad de un producto-receta derivada del stock de insumos.
  /// GET /api/v1/recipes/:uuid/availability (AC-03).
  Future<Map<String, dynamic>> fetchRecipeAvailability(String uuid) async {
    try {
      final response = await _dio.get('/api/v1/recipes/$uuid/availability');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 11b. BROADCAST PROMOTIONS — Difusión de promociones (F033)
  // Contrato: specs/033-difusion-promociones/plan.md §4.
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Módulo "Promociones" (F033): central de campañas para avisarles a
  // los clientes por WhatsApp / link público. Endpoints privados bajo
  // JWT; el detalle de la promo pública (sin JWT) lo sirve admin-web.
  //
  // NOTA — la sección 11 (legacy combo-promos, migraciones 018-019)
  // también usa `/api/v1/promotions`. El backend de F033 resuelve la
  // convivencia de rutas (auditoría T-01); estos métodos siguen el
  // contrato del plan §4 tal cual.

  /// Lista las promociones de difusión del tenant.
  ///
  /// [filter] → `active` | `expired` | `draft` (opcional).
  /// Devuelve el cuerpo crudo `{ data: [...], meta: {...} }`.
  Future<Map<String, dynamic>> listBroadcastPromotions({
    String? filter,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final params = <String, dynamic>{'limit': limit, 'offset': offset};
      if (filter != null && filter.isNotEmpty) params['filter'] = filter;
      final response = await _dio.get('/api/v1/broadcast-promotions',
          queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea una promoción de difusión. El backend asigna el
  /// `public_token`. Devuelve la promoción creada (clave `data`).
  Future<Map<String, dynamic>> createBroadcastPromotion(
      Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/broadcast-promotions', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Detalle completo de una promoción (items + métricas).
  Future<Map<String, dynamic>> getBroadcastPromotion(String id) async {
    try {
      final response = await _dio.get('/api/v1/broadcast-promotions/$id');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Edita una promoción que aún no fue enviada. Devuelve la promoción
  /// resultante.
  Future<Map<String, dynamic>> updateBroadcastPromotion(
      String id, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.patch('/api/v1/broadcast-promotions/$id', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Elimina una promoción (cascada items + deliveries).
  Future<void> deleteBroadcastPromotion(String id) async {
    try {
      await _dio.delete('/api/v1/broadcast-promotions/$id');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Resuelve la audiencia segmentada de una promoción.
  ///
  /// [filter] → `frequent` | `vip` | `dormant` | `recent` | `all` |
  /// `manual`. Cuando es `manual` se envían los [customerIds] elegidos
  /// a mano. Devuelve el cuerpo crudo `{ data: [...], meta: {count} }`.
  Future<Map<String, dynamic>> fetchPromotionAudience(
    String promotionId, {
    required String filter,
    List<String>? customerIds,
  }) async {
    try {
      final body = <String, dynamic>{'filter': filter};
      if (customerIds != null && customerIds.isNotEmpty) {
        body['customer_ids'] = customerIds;
      }
      final response = await _dio.post(
          '/api/v1/broadcast-promotions/$promotionId/audience',
          data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea los registros de delivery (estado `queued`) para una promo y
  /// devuelve la cola lista para enviar.
  ///
  /// [channel] → `whatsapp` | `link` | `qr` | `manual`. El backend
  /// deduplica por `(promo, cliente, canal)` y pre-genera el mensaje
  /// personalizado de cada delivery.
  Future<Map<String, dynamic>> createPromotionDeliveries(
    String promotionId, {
    required List<String> customerIds,
    required String channel,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/broadcast-promotions/$promotionId/deliveries',
        data: {'customer_ids': customerIds, 'channel': channel},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Marca el estado de un delivery después de que el dueño tocó
  /// "enviar" / "saltar" en la cola de WhatsApp.
  ///
  /// [status] → `sent` | `skipped`.
  Future<Map<String, dynamic>> updatePromotionDelivery(
    String promotionId,
    String deliveryId, {
    required String status,
  }) async {
    try {
      final response = await _dio.patch(
        '/api/v1/broadcast-promotions/$promotionId/deliveries/$deliveryId',
        data: {'status': status},
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Sube una foto/banner para una promoción de difusión y devuelve el
  /// `image_url` resultante.
  ///
  /// Cross-platform: lee los BYTES de la imagen (no la ruta de archivo)
  /// — funciona en Flutter web igual que en móvil. Reusa el mismo
  /// pipeline de normalización de imágenes que el logo / la foto de
  /// producto ([imageMultipart]).
  Future<Map<String, dynamic>> uploadPromotionImage(XFile image) async {
    try {
      final formData = FormData.fromMap({
        'image': await imageMultipart(image, prefix: 'promo'),
      });
      final response = await _dio.post(
        '/api/v1/broadcast-promotions/upload-image',
        data: formData,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 12. PURCHASE ORDERS — Órdenes de compra (Feature 002)
  // Contrato: specs/002-ordenes-compra/plan.md §4.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lista las órdenes de compra del tenant.
  /// GET /api/v1/purchase-orders — filtro opcional por `status`.
  Future<List<Map<String, dynamic>>> fetchPurchaseOrders({
    String? status,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/purchase-orders',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Obtiene una orden de compra con sus ítems.
  /// GET /api/v1/purchase-orders/:uuid (AC-01).
  Future<Map<String, dynamic>> fetchPurchaseOrder(String uuid) async {
    try {
      final response = await _dio.get('/api/v1/purchase-orders/$uuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea una orden de compra. POST /api/v1/purchase-orders.
  /// El cuerpo lleva el `id` que genera el cliente (idempotencia — Art. II).
  Future<Map<String, dynamic>> createPurchaseOrder(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/purchase-orders', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Actualiza una orden de compra en `borrador`.
  /// PATCH /api/v1/purchase-orders/:uuid (plan §4 — editar solo en borrador).
  Future<Map<String, dynamic>> updatePurchaseOrder(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.patch('/api/v1/purchase-orders/$uuid', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Elimina (soft delete) una orden de compra.
  /// DELETE /api/v1/purchase-orders/:uuid.
  Future<void> deletePurchaseOrder(String uuid) async {
    try {
      await _dio.delete('/api/v1/purchase-orders/$uuid');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Envía la PO al proveedor: pasa a `enviada` y devuelve la URL `wa.me`
  /// con la lista completa de ítems (FR-04, AC-02).
  /// POST /api/v1/purchase-orders/:uuid/send → `{status, whatsapp_url}`.
  Future<Map<String, dynamic>> sendPurchaseOrder(String uuid) async {
    try {
      final response = await _dio.post('/api/v1/purchase-orders/$uuid/send');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Recibe la PO: entra stock de cada ítem vía kardex `purchase_receipt`
  /// y la PO pasa a `recibida`. Idempotente por UUID de PO (FR-05, AC-03/04).
  /// POST /api/v1/purchase-orders/:uuid/receive → `{data:PurchaseOrder}`.
  Future<Map<String, dynamic>> receivePurchaseOrder(String uuid) async {
    try {
      final response = await _dio.post('/api/v1/purchase-orders/$uuid/receive');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Genera PO(s) `borrador` pre-llenadas desde las sugerencias de reorden,
  /// agrupadas por proveedor (FR-07, AC-07).
  /// POST /api/v1/purchase-orders/from-reorder → `{data:[PurchaseOrder]}`.
  Future<List<Map<String, dynamic>>> createPurchaseOrdersFromReorder() async {
    try {
      final response = await _dio.post('/api/v1/purchase-orders/from-reorder');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 10b. WORK ORDERS — trabajos de fabricación/reparación (Feature 003)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lista los trabajos del tenant, opcionalmente filtrados por estado o
  /// tipo. GET /api/v1/work-orders (plan §4).
  Future<List<Map<String, dynamic>>> fetchWorkOrders({
    String? status,
    String? type,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/work-orders',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
          if (type != null && type.isNotEmpty) 'type': type,
        },
      );
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Obtiene un trabajo con sus ítems y pagos.
  /// GET /api/v1/work-orders/:uuid (AC-01).
  Future<Map<String, dynamic>> fetchWorkOrder(String uuid) async {
    try {
      final response = await _dio.get('/api/v1/work-orders/$uuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Crea un trabajo. POST /api/v1/work-orders.
  /// El cuerpo lleva el `id` que genera el cliente (idempotencia — Art. II).
  Future<Map<String, dynamic>> createWorkOrder(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/work-orders', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Actualiza un trabajo. PATCH /api/v1/work-orders/:uuid.
  /// Los ítems solo se editan en `cotizacion`/`aprobada`; pasar `status`
  /// transiciona el ciclo de vida — `terminada` dispara el consumo de
  /// material en el backend (plan §4).
  Future<Map<String, dynamic>> updateWorkOrder(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.patch('/api/v1/work-orders/$uuid', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Elimina (soft delete) un trabajo. DELETE /api/v1/work-orders/:uuid.
  Future<void> deleteWorkOrder(String uuid) async {
    try {
      await _dio.delete('/api/v1/work-orders/$uuid');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Registra un anticipo del cliente contra el trabajo (FR-04, AC-02).
  /// El backend valida que el anticipo no exceda el saldo pendiente.
  /// POST /api/v1/work-orders/:uuid/payments → `{data:WorkOrder}`.
  Future<Map<String, dynamic>> addWorkOrderPayment(
      String uuid, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/work-orders/$uuid/payments', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Comparte la cotización con el cliente por WhatsApp (FR-06, AC-06).
  /// POST /api/v1/work-orders/:uuid/share → `{whatsapp_url, message}`.
  Future<Map<String, dynamic>> shareWorkOrder(String uuid) async {
    try {
      final response = await _dio.post('/api/v1/work-orders/$uuid/share');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 11. PROMOTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchPromotions() async {
    try {
      final response = await _dio.get('/api/v1/promotions');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createPromotion(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/promotions', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchPromotionSuggestions() async {
    try {
      final response = await _dio.get('/api/v1/promotions/suggestions');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> applyPromotionToPOS(String promotionUuid) async {
    try {
      final response = await _dio.post('/api/v1/promotions/apply-to-pos',
          data: {'promotion_uuid': promotionUuid});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Calls the AI banner generator. Returns the public URL of the
  /// generated banner (or a data: URL when storage is not configured).
  ///
  /// V2 (2026-04): además de los inputs V1 (`promoName`, `productNames`,
  /// `discountText`, `tone`) ahora enviamos la propuesta de valor
  /// completa — nombre del negocio, título del combo, precios
  /// formateados y cadena de ahorro — para que el prompt del backend
  /// inyecte tipografía comercial legible en la imagen generada. Todos
  /// los campos V2 son opcionales: un backend viejo los ignorará, uno
  /// nuevo los usará para mejorar el banner.
  Future<Map<String, dynamic>> generatePromoBanner({
    required String promoName,
    required List<String> productNames,
    String discountText = '',
    String tone = 'vibrante',
    String? tenantName,
    String? comboTitle,
    String? normalPriceStr,
    String? promoPriceStr,
    String? discountStr,
    String? savingsStr,
    // V3 — image sourcing. "CATALOG_PHOTOS" pasa las fotos reales del
    // tenant a Gemini como anclas visuales; "AI_GENERATED" las manda
    // a generar desde cero. Null/vacío → backend decide default.
    String? imageSourceType,
    List<String>? catalogImageUrls,
  }) async {
    try {
      final data = <String, dynamic>{
        'promo_name': promoName,
        'products': productNames,
        'discount_text': discountText,
        'tone': tone,
      };
      void addIfPresent(String key, String? v) {
        if (v != null && v.trim().isNotEmpty) {
          data[key] = v.trim();
        }
      }

      addIfPresent('tenant_name', tenantName);
      addIfPresent('combo_title', comboTitle);
      addIfPresent('normal_price_str', normalPriceStr);
      addIfPresent('promo_price_str', promoPriceStr);
      addIfPresent('discount_str', discountStr);
      addIfPresent('savings_str', savingsStr);
      addIfPresent('image_source_type', imageSourceType);
      if (catalogImageUrls != null && catalogImageUrls.isNotEmpty) {
        // Filtramos vacíos/null antes de enviar: el backend sólo usará
        // las URLs que pueda descargar, pero evitamos pasarle basura.
        final clean = catalogImageUrls
            .where((u) => u.trim().isNotEmpty)
            .toList(growable: false);
        if (clean.isNotEmpty) {
          data['catalog_image_urls'] = clean;
        }
      }

      final response = await _dio.post(
        '/api/v1/marketing/generate-banner',
        data: data,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 12. ONLINE STORE / CATALOG
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchStoreConfig() async {
    try {
      final response = await _dio.get('/api/v1/store/config');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// F041 — catálogo dinámico de módulos/tipos. Soporta ETag/304: si
  /// [etag] coincide con el del servidor, devuelve `notModified: true` y
  /// `data: null` (la app conserva su cache). Devuelve además el ETag
  /// nuevo para guardarlo.
  Future<({Map<String, dynamic>? data, String etag, bool notModified})>
      fetchBusinessCatalog({String? etag}) async {
    try {
      final response = await _dio.get(
        '/api/v1/catalog',
        options: Options(
          headers:
              etag != null && etag.isNotEmpty ? {'If-None-Match': etag} : null,
          // 304 es una respuesta válida (no error) para el flujo de cache.
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final newEtag = (response.headers.value('etag') ?? etag ?? '').toString();
      if (response.statusCode == 304) {
        return (data: null, etag: newEtag, notModified: true);
      }
      return (data: _extractData(response), etag: newEtag, notModified: false);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateStoreConfig(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/store/config', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> updateStoreStatus(bool isOpen) async {
    try {
      await _dio.patch('/api/v1/store/status', data: {'is_open': isOpen});
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Fetches the store slug and the public catalog URL. The backend
  /// auto-provisions a slug from the business name the first time it
  /// is called, so this endpoint is safe to hit from the Marketing
  /// Hub without a previous setup step.
  ///
  /// Returns `{slug, base_url, public_url}`. Throws [AppError] on
  /// network or 5xx failures — the caller decides how to degrade.
  Future<Map<String, dynamic>> fetchStoreSlug() async {
    try {
      final response = await _dio.get('/api/v1/store/slug');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Updates the tenant's store slug. Surfaces the backend's 409
  /// Conflict as [AppError.statusCode] == 409 so the UI can show a
  /// specific "ya está en uso" message instead of a generic error.
  Future<Map<String, dynamic>> updateStoreSlug(String slug) async {
    try {
      final response = await _dio.patch(
        '/api/v1/store/slug',
        data: {'slug': slug},
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Public — no auth required
  Future<Map<String, dynamic>> fetchCatalog(String slug) async {
    try {
      final response = await _dio.get('/api/v1/store/$slug/catalog');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Public — no auth required
  Future<Map<String, dynamic>> fetchCatalogProduct(
      String slug, String uuid) async {
    try {
      final response = await _dio.get('/api/v1/store/$slug/product/$uuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Public — no auth required
  Future<Map<String, dynamic>> createWebOrder(
      String slug, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/store/$slug/order', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Public — no auth required
  Future<Map<String, dynamic>> fetchWebOrderStatus(
      String slug, String uuid) async {
    try {
      final response = await _dio.get('/api/v1/store/$slug/order/$uuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 13. WHATSAPP / PAYMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchPaymentQR({
    required double amount,
    required String method,
  }) async {
    try {
      final response = await _dio.get('/api/v1/payments/qr',
          queryParameters: {'amount': amount, 'method': method});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 14. ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Branch-scoped query params — injected into all analytics calls
  /// so the backend's ResolveBranchScope picks up the active sede.
  Map<String, dynamic> _branchParams([Map<String, dynamic>? extra]) {
    final params = <String, dynamic>{};
    if (currentBranchId != null && currentBranchId!.isNotEmpty) {
      params['branch_id'] = currentBranchId!;
    }
    if (extra != null) params.addAll(extra);
    return params;
  }

  Future<Map<String, dynamic>> fetchAnalyticsDashboard() async {
    try {
      final response = await _dio.get('/api/v1/analytics/dashboard',
          queryParameters: _branchParams());
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchTopProducts(
      {String period = '7d'}) async {
    try {
      final response = await _dio.get('/api/v1/analytics/top-products',
          queryParameters: _branchParams({'period': period}));
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchPhotoCoverage() async {
    try {
      final response = await _dio.get('/api/v1/analytics/photo-coverage',
          queryParameters: _branchParams());
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchSalesByEmployee() async {
    try {
      final response = await _dio.get('/api/v1/analytics/sales-by-employee',
          queryParameters: _branchParams());
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchInventoryHealth() async {
    try {
      final response = await _dio.get('/api/v1/analytics/inventory-health',
          queryParameters: _branchParams());
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchIngestionMethod() async {
    try {
      final response = await _dio.get('/api/v1/analytics/ingestion-method',
          queryParameters: _branchParams());
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 15a. BUSINESS PROFILE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchBusinessProfile() async {
    try {
      final response = await _dio.get('/api/v1/store/profile');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateBusinessProfile(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch('/api/v1/store/profile', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 15b. LOGO IA
  // ═══════════════════════════════════════════════════════════════════════════

  /// PUBLIC endpoint used during onboarding (BEFORE the tenant
  /// exists). Generates a preview logo, returns the URL — the URL
  /// is then sent in the registerTenantFull payload so the tenant
  /// is created with the logo in place.
  Future<Map<String, dynamic>> previewLogoIA({
    required String businessName,
    required String businessType,
    required String details,
  }) async {
    try {
      final response = await _dio.post('/api/v1/auth/preview-logo', data: {
        'business_name': businessName,
        'business_type': businessType,
        'details': details,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// PUBLIC counterpart of previewLogoIA — uploads a gallery image
  /// before the tenant exists. Used by the onboarding logo step.
  ///
  /// Cross-platform: reads the picked image as BYTES so it works on
  /// Flutter web (where there is no filesystem and `XFile.path` is a
  /// blob URL) and on mobile alike. See [logoMultipart].
  Future<Map<String, dynamic>> previewLogoUpload(XFile logo) async {
    try {
      final formData = FormData.fromMap({
        'logo': await logoMultipart(logo),
      });
      final response = await _dio.post(
        '/api/v1/auth/preview-logo-upload',
        data: formData,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> generateLogoAI({
    required String businessName,
    required String businessType,
    String? details,
  }) async {
    try {
      final response = await _dio.post('/api/v1/tenant/generate-logo', data: {
        'business_name': businessName,
        'business_type': businessType,
        if (details != null && details.isNotEmpty) 'details': details,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Uploads a custom logo for an already-registered tenant.
  ///
  /// Cross-platform: reads the picked image as BYTES (works on web and
  /// mobile). See [logoMultipart].
  Future<Map<String, dynamic>> uploadLogo(XFile logo) async {
    try {
      final formData = FormData.fromMap({
        'logo': await logoMultipart(logo),
      });
      final response =
          await _dio.post('/api/v1/tenant/upload-logo', data: formData);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Builds a Dio [MultipartFile] for a picked logo [XFile].
  ///
  /// Spec 010 §9 / D1: the image is first normalized to a downsized **PNG**
  /// via [normalizeImageForUpload] (the browser decodes HEIC on web;
  /// `package:image` re-encodes on mobile). The resulting part is always
  /// sent as `image/png` with a `.png` filename, so the Supabase
  /// `store-logos` bucket — which accepts png but rejects `image/heic` —
  /// always receives an accepted format. PNG is used (not JPEG) so a logo
  /// generated by an AI with a transparent background keeps its
  /// transparency. This is shared by onboarding (`previewLogoUpload`) and
  /// the business profile (`uploadLogo`).
  ///
  /// Reading bytes (not a filesystem path) keeps this working on Flutter
  /// web, where there is no `dart:io` filesystem and `XFile.path` is only
  /// a blob URL.
  ///
  /// Throws [ImageNormalizationException] (Spanish message) when the
  /// picked image cannot be decoded; callers surface it to the merchant.
  @visibleForTesting
  static Future<MultipartFile> logoMultipart(XFile logo) =>
      _imageMultipart(logo, prefix: 'logo');

  /// Builds a Dio [MultipartFile] for any picked image [XFile] — a store
  /// logo or a product photo (Spec 013 / D2, D3).
  ///
  /// The image is normalized to a downsized **PNG** via
  /// [normalizeImageForUpload] and always sent as `image/png` with a
  /// `.png` filename ([prefix]-<uuid>.png). Normalizing on every platform
  /// is what makes an iPhone HEIC photo render on Android, and reading
  /// BYTES (not a filesystem path) is what makes this work on Flutter web.
  ///
  /// Throws [ImageNormalizationException] (Spanish message) when the
  /// picked image cannot be decoded; callers surface it to the merchant.
  @visibleForTesting
  static Future<MultipartFile> imageMultipart(XFile image,
          {required String prefix}) =>
      _imageMultipart(image, prefix: prefix);

  static Future<MultipartFile> _imageMultipart(XFile image,
      {required String prefix}) async {
    final pngBytes = await normalizeImageForUpload(image);
    return MultipartFile.fromBytes(
      pngBytes,
      filename: '$prefix-${const Uuid().v4()}.png',
      contentType: DioMediaType('image', 'png'),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 16. ROCKOLA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Public — no auth
  Future<Map<String, dynamic>> suggestSong(
      String slug, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/rockola/$slug/suggest', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchPendingSongs() async {
    try {
      final response = await _dio.get('/api/v1/rockola/pending');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> markSongPlayed(String uuid) async {
    try {
      await _dio.patch('/api/v1/rockola/$uuid/played');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> searchSongs(String query) async {
    try {
      final response = await _dio
          .get('/api/v1/rockola/search', queryParameters: {'q': query});
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 17. REAL-TIME ACCOUNT (Public)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchAccountRealTime(String orderUuid) async {
    try {
      final response = await _dio.get('/api/v1/account/$orderUuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> verifyAccountPhone(
      String orderUuid, String phone) async {
    try {
      final response = await _dio
          .post('/api/v1/account/$orderUuid/verify', data: {'phone': phone});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 18. SOS / PÁNICO SILENCIOSO
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchSosConfig() async {
    try {
      final response = await _dio.get('/api/v1/sos/config');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> saveSosConfig(Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/api/v1/sos/config', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> triggerSosPanic({
    double? latitude,
    double? longitude,
    String triggeredFrom = 'pos',
  }) async {
    try {
      final response = await _dio.post('/api/v1/sos/trigger', data: {
        'latitude': latitude,
        'longitude': longitude,
        'triggered_from': triggeredFrom,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchSosHistory({
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get('/api/v1/sos/history',
          queryParameters: {'page': page, 'per_page': perPage});
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 19. ABONOS / PAGOS PARCIALES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> registerPayment(
      String orderUuid, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/orders/$orderUuid/payments', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchOrderPayments(String orderUuid) async {
    try {
      final response = await _dio.get('/api/v1/orders/$orderUuid/payments');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> registerSplitPayments(
      String orderUuid, Map<String, dynamic> data) async {
    try {
      final response = await _dio
          .post('/api/v1/orders/$orderUuid/split-payments', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 20. HISTORIAL DE CUENTAS DEL CLIENTE (Public con client_token)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchClientAccountHistory({
    required String clientToken,
    required String phone,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/account/history',
        queryParameters: {
          'phone': phone,
          'page': page,
          'per_page': perPage,
        },
        options: Options(headers: {'X-Client-Token': clientToken}),
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> requestClientOtp(
      String orderUuid, String phone) async {
    try {
      final response = await _dio.post(
        '/api/v1/account/$orderUuid/verify',
        data: {'phone': phone, 'action': 'request_otp'},
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> verifyClientOtp(
      String orderUuid, String phone, String otpCode) async {
    try {
      final response = await _dio.post(
        '/api/v1/account/$orderUuid/verify',
        data: {'phone': phone, 'action': 'verify_otp', 'otp_code': otpCode},
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 21. SYNC OFFLINE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> syncBatch(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/sync/batch', data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEALTHCHECK
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> ping() async {
    try {
      final response = await _dio.get('/ping');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _extractData(Response response) {
    final body = response.data as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? body;
  }

  List<Map<String, dynamic>> _extractList(Response response) {
    final body = response.data as Map<String, dynamic>;
    final list = (body['data'] as List?) ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 20. FLOOR PLAN TABLES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchTables() async {
    try {
      final response = await _dio.get('/api/v1/tables');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> syncTables(
      List<Map<String, dynamic>> tables) async {
    try {
      final response = await _dio.post('/api/v1/tables/sync', data: {
        'tables': tables,
      });
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENT METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchPaymentMethods() async {
    try {
      final response = await _dio.get('/api/v1/store/payment-methods');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createPaymentMethod(
      Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/store/payment-methods', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deletePaymentMethod(String id) async {
    try {
      await _dio.delete('/api/v1/store/payment-methods/$id');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Partial update for a payment method — used by the toggle-active
  /// switch in the hub UI. Accepts any subset of {name,
  /// account_details, is_active, provider, qr_image_url}; the
  /// backend ignores keys you don't send.
  Future<Map<String, dynamic>> updatePaymentMethod(
      String id, Map<String, dynamic> patch) async {
    try {
      final response = await _dio.patch(
        '/api/v1/store/payment-methods/$id',
        data: patch,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Uploads a QR code image for an existing payment method.
  ///
  /// The backend stores it in the `payment-qrs` bucket (R2/Supabase)
  /// and returns the full updated record with `qr_image_url`.
  ///
  /// `filePath` must point to a local image (≤ 3 MB). `mimeType`
  /// defaults to image/png — the gallery picker on Android/iOS will
  /// usually hand us PNG or JPEG.
  Future<Map<String, dynamic>> uploadPaymentMethodQR({
    required String id,
    required String filePath,
    String mimeType = 'image/png',
    String filename = 'qr.png',
  }) async {
    try {
      final form = FormData.fromMap({
        'qr': await MultipartFile.fromFile(
          filePath,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final response = await _dio.post(
        '/api/v1/store/payment-methods/$id/qr',
        data: form,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FINANCIAL ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchFinancialSummary({
    String period = 'today',
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/analytics/financial-summary',
        queryParameters: _branchParams({'period': period}),
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Full dashboard payload — same endpoint, but with the optional
  /// employee/source/payment-method filters wired through.
  Future<Map<String, dynamic>> fetchFinancialSummaryFull({
    String period = 'today',
    String? employee,
    String? source,
    String? paymentMethod,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final params = _branchParams({'period': period});
      if (employee != null && employee.isNotEmpty) {
        params['employee'] = employee;
      }
      if (source != null && source.isNotEmpty) params['source'] = source;
      if (paymentMethod != null && paymentMethod.isNotEmpty) {
        params['payment_method'] = paymentMethod;
      }
      if (since != null) params['since'] = since.toUtc().toIso8601String();
      if (until != null) params['until'] = until.toUtc().toIso8601String();
      final response = await _dio.get(
        '/api/v1/analytics/financial-summary',
        queryParameters: params,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// GET /analytics/products-insights — consolidated product
  /// intelligence panel: top sellers, slow movers, items near expiry.
  Future<Map<String, dynamic>> fetchProductInsights({
    String period = '30d',
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/analytics/products-insights',
        queryParameters: _branchParams({'period': period}),
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<dynamic>> fetchSalesHistoryByPeriod({
    String period = 'today',
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/analytics/sales-history',
        queryParameters: _branchParams({
          'period': period,
          'page': page,
          'per_page': perPage,
        }),
      );
      final body = response.data as Map<String, dynamic>;
      return (body['data'] as List?) ?? [];
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIADO HANDSHAKE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> initFiado({
    required String customerName,
    required String customerPhone,
    required int totalAmount,
    String customerEmail = '',
    String idempotencyKey = '',
  }) async {
    try {
      final response = await _dio.post('/api/v1/fiado/init', data: {
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_email': customerEmail,
        'total_amount': totalAmount,
        'idempotency_key': idempotencyKey,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> checkFiadoStatus(String token) async {
    try {
      final response = await _dio.get('/api/v1/fiado/$token/status');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PANIC BUTTON
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchPanicConfig() async {
    try {
      final response = await _dio.get('/api/v1/store/panic-config');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> updatePanicMessage(
    String? message, {
    bool? includeAddress,
    bool? includeGPS,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (message != null) data['panic_message'] = message;
      if (includeAddress != null) {
        data['panic_include_address'] = includeAddress;
      }
      if (includeGPS != null) data['panic_include_gps'] = includeGPS;
      await _dio.patch('/api/v1/store/panic-config', data: data);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createEmergencyContact(
      Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/store/panic-config/contacts', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deleteEmergencyContact(String id) async {
    try {
      await _dio.delete('/api/v1/store/panic-config/contacts/$id');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> triggerPanic({
    double liveLatitude = 0,
    double liveLongitude = 0,
  }) async {
    try {
      await _dio.post('/api/v1/store/panic/trigger', data: {
        'live_latitude': liveLatitude,
        'live_longitude': liveLongitude,
      });
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Histórico de alertas de pánico (Spec 057) — cada alerta con sus
  /// entregas por contacto (estado sent/failed/skipped/pending).
  Future<List<Map<String, dynamic>>> fetchPanicAlerts() async {
    try {
      final response = await _dio.get('/api/v1/store/panic/alerts');
      final data = response.data['data'];
      if (data is List) return data.cast<Map<String, dynamic>>();
      return const [];
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CREDITS (EL CUADERNO) - detail + abono
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchCreditDetail(String id) async {
    try {
      final response = await _dio.get('/api/v1/credits/$id');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> registerAbono(
    String creditId, {
    required int amount,
    String method = 'cash',
    String note = '',
    String? receiptImageUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'amount': amount,
        'payment_method': method,
        'note': note,
      };
      if (receiptImageUrl != null && receiptImageUrl.isNotEmpty) {
        body['receipt_image_url'] = receiptImageUrl;
      }
      final response =
          await _dio.post('/api/v1/credits/$creditId/payments', data: body);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Append an amount to an already-accepted open fiado. Skips the WhatsApp
  /// handshake — the owner already authorized this line of credit when the
  /// customer originally accepted it.
  Future<Map<String, dynamic>> appendToFiado(
    String creditId, {
    required int totalAmount,
    String note = '',
  }) async {
    try {
      final response = await _dio.post('/api/v1/credits/$creditId/append',
          data: {'total_amount': totalAmount, 'note': note});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Close a fiado manually — writes off any residual balance with a
  /// CreditPayment of method='write_off' and marks the account as paid.
  /// Used when the tendero negotiates a discount or forgives a leftover.
  /// When the account still has a positive balance, the backend refuses
  /// unless [force] is true (protects against accidental closures).
  Future<Map<String, dynamic>> closeFiado(
    String creditId, {
    String reason = '',
    bool force = false,
  }) async {
    try {
      final response = await _dio.post('/api/v1/credits/$creditId/close',
          data: {'reason': reason, 'force': force});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Cancel a pending fiado: linked sales are voided, stock is returned
  /// to the products, and the account flips to status='cancelled'. Only
  /// valid while the customer hasn't accepted the handshake (backend
  /// rejects with 409 otherwise).
  Future<Map<String, dynamic>> cancelFiado(
    String creditId, {
    String reason = '',
  }) async {
    try {
      final response = await _dio
          .post('/api/v1/credits/$creditId/cancel', data: {'reason': reason});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Express payment setup — writes the tenant's primary method (name,
  /// account number, holder) in one PATCH. The public fiado portal
  /// reads these three fields and renders the two copy buttons.
  /// Any omitted field is left untouched on the server.
  Future<Map<String, dynamic>> updatePaymentConfig({
    String? methodName,
    String? accountNumber,
    String? accountHolder,
  }) async {
    final data = <String, dynamic>{};
    if (methodName != null) data['payment_method_name'] = methodName;
    if (accountNumber != null) data['payment_account_number'] = accountNumber;
    if (accountHolder != null) data['payment_account_holder'] = accountHolder;
    try {
      final response =
          await _dio.patch('/api/v1/store/payment-config', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Ask the backend to build a dynamic-QR payload for the current
  /// tenant + amount. Used by the "Transferencia" checkout flow so the
  /// cashier can show a QR where the amount is locked and the customer
  /// cannot edit it. Zero merchant fees — the Nequi/Daviplata/
  /// Bancolombia app confirms to the tendero via SMS.
  Future<Map<String, dynamic>> generateDynamicQR({
    required int amount,
    String? paymentMethodId,
  }) async {
    try {
      final data = <String, dynamic>{'amount': amount};
      if (paymentMethodId != null && paymentMethodId.isNotEmpty) {
        data['payment_method_id'] = paymentMethodId;
      }
      final response =
          await _dio.post('/api/v1/payments/generate-dynamic-qr', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchNotifications() async {
    try {
      final response = await _dio.get('/api/v1/notifications');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> markNotificationsRead() async {
    try {
      await _dio.post('/api/v1/notifications/read');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ONLINE ORDERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetches online orders. Optional [status] narrows to a single
  /// state ("pending", "accepted", "rejected", "completed"). The
  /// active branch is attached automatically via currentBranchId so
  /// a sede-scoped KDS doesn't leak other branches' pedidos.
  Future<List<dynamic>> fetchOnlineOrders({String? status}) async {
    try {
      final params = <String, dynamic>{};
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (currentBranchId != null && currentBranchId!.isNotEmpty) {
        params['branch_id'] = currentBranchId!;
      }
      final response = await _dio.get(
        '/api/v1/online-orders',
        queryParameters: params.isEmpty ? null : params,
      );
      return (response.data['data'] as List?) ?? [];
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> updateOnlineOrderStatus(String id, String status) async {
    try {
      await _dio.patch('/api/v1/online-orders/$id', data: {'status': status});
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE TAB — public session + partial payments (abonos)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetches the live tab via the PUBLIC endpoint. Same payload the
  /// customer sees on the QR page so the tendero and the client are
  /// looking at the exact same numbers (items with added_at, abonos,
  /// paid_amount, remaining_balance, payment_methods). No auth.
  Future<Map<String, dynamic>> fetchPublicTableSession(
      String sessionToken) async {
    try {
      final response = await _dio.get(
        '/api/v1/public/table-sessions/$sessionToken',
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Authenticated: tendero registers a manual abono from the POS
  /// (customer handed them cash / paid by transfer in person).
  /// Lands as APPROVED directly so it counts against the remaining
  /// balance without an extra confirmation step.
  Future<Map<String, dynamic>> registerPartialPayment({
    required String orderId,
    required double amount,
    required String paymentMethod,
    String paymentMethodId = '',
    String notes = '',
    String? receiptImageUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'order_id': orderId,
        'amount': amount,
        'payment_method': paymentMethod,
        'payment_method_id': paymentMethodId,
        'notes': notes,
      };
      if (receiptImageUrl != null && receiptImageUrl.isNotEmpty) {
        body['receipt_image_url'] = receiptImageUrl;
      }
      final response = await _dio.post(
        '/api/v1/orders/partial-payments',
        data: body,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Reverse-QR confirm: tendero / mesero scanned the customer's
  /// QR, takes the cash, and we flip the abono to APPROVED. Returns
  /// the updated row + an `already` flag (true when the same QR
  /// had already been confirmed — the UI can show "ya cobrado"
  /// instead of double-counting the abono).
  Future<Map<String, dynamic>> confirmPartialPayment(String paymentId) async {
    try {
      final response = await _dio.post(
        '/api/v1/orders/payments/$paymentId/confirm',
      );
      final raw = response.data;
      if (raw is Map<String, dynamic>) return raw;
      return <String, dynamic>{};
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Owner sets the 4-digit PIN that cashiers will enter to unlock restricted
  /// actions. Fails with 403 if the caller is not owner/admin.
  Future<void> setOwnerPin(String pin) async {
    try {
      await _dio.post('/api/v1/tenant/owner-pin', data: {'pin': pin});
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Cashier submits the PIN dictated by the owner. Returns true on match.
  /// Returns false on wrong PIN (401/403) or if the owner has not yet set one.
  /// Throws AppError on network failures or timeout.
  Future<bool> verifyOwnerPin(String pin) async {
    try {
      final resp = await _dio.post(
        '/api/v1/tenant/owner-pin/verify',
        data: {'pin': pin},
      ).timeout(const Duration(seconds: 5));
      final body = resp.data;
      return body is Map && body['ok'] == true;
    } on TimeoutException catch (e) {
      // Network is hung — caller should show a connectivity message.
      throw AppError.fromDioException(
        DioException(
          requestOptions:
              RequestOptions(path: '/api/v1/tenant/owner-pin/verify'),
          type: DioExceptionType.connectionTimeout,
          error: e,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return false;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw AppError.fromDioException(e);
      }
      return false;
    }
  }

  /// Creates a support ticket for the current tenant. The backend is
  /// the source of truth for subject-length clipping (160 chars) and
  /// whitespace rejection — we pass user input through verbatim so
  /// server-side error messages stay authoritative.
  Future<void> createSupportTicket({
    required String subject,
    required String message,
    String? category,
    String? priority,
  }) async {
    try {
      await _dio.post('/api/v1/support/tickets', data: {
        'subject': subject,
        'message': message,
        'category': category ?? 'OTHER',
        'priority': priority ?? 'NORMAL',
      });
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchTenantTickets() async {
    try {
      final response = await _dio.get('/api/v1/support/tickets');
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchTicketDetails(String id) async {
    try {
      final response = await _dio.get('/api/v1/support/tickets/$id');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> addTicketMessage(
      String ticketId, String content) async {
    try {
      final response = await _dio.post(
        '/api/v1/support/tickets/$ticketId/messages',
        data: {'content': content},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBSCRIPTION & BILLING (Feature 008 — planes + ePayco)
  //
  // Contrato: specs/008-planes-suscripcion-epayco/plan.md §4.
  //   GET  /api/v1/subscription/plans    → catálogo (Gratis, Pro)
  //   GET  /api/v1/subscription/status   → estado del tenant
  //   POST /api/v1/subscription/checkout → datos del checkout de ePayco
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET /subscription/plans — catálogo de planes (Gratis, Pro
  /// mensual/anual). El catálogo vive en config del backend (D4), no
  /// es editable por UI.
  Future<List<SubscriptionPlan>> fetchPlans() async {
    try {
      final response = await _dio.get('/api/v1/subscription/plans');
      final list = _extractList(response);
      return list.map(SubscriptionPlan.fromJson).toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// GET /subscription/status — estado actual de la suscripción del
  /// tenant. El backend ya degrada trial/Pro vencido a FREE (AC-08),
  /// así que la UI confía en lo que recibe.
  Future<SubscriptionStatus> fetchSubscriptionStatus() async {
    try {
      final response = await _dio.get('/api/v1/subscription/status');
      return SubscriptionStatus.fromJson(_extractData(response));
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// POST /subscription/checkout — pide al backend los datos para
  /// abrir el checkout de ePayco de un plan. El webhook de
  /// confirmación es la fuente de verdad de la promoción a Pro (D2);
  /// esta llamada solo arma el checkout.
  ///
  /// [plan] es el id del plan (`pro`); [interval] es `mensual` |
  /// `anual`.
  Future<CheckoutSession> createCheckout({
    required String plan,
    required String interval,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/subscription/checkout',
        data: {'plan': plan, 'interval': interval},
      );
      return CheckoutSession.fromJson(_extractData(response));
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ── Error envelope helpers ───────────────────────────────────────────────
  //
  // The Go backend returns `{ "error": "...", "error_code": "..." }` for
  // soft-paywall and token-expiry responses. These helpers narrow the
  // dynamic Dio response body safely — wrapping in try/catch so a
  // malformed payload never takes down the interceptor chain.

  String? _extractErrorCode(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error_code'] is String) {
      return data['error_code'] as String;
    }
    return null;
  }

  String? _extractErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      // New shape carries the human-readable copy under `message`;
      // legacy shape kept the user-facing string under `error`.
      if (data['message'] is String && (data['message'] as String).isNotEmpty) {
        return data['message'] as String;
      }
      if (data['error'] is String) {
        return data['error'] as String;
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CART-SESSION LOCKS (multi-employee concurrency)
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET /api/v1/carts/sessions — live snapshot of who currently
  /// holds each cart slot in the caller's tenant + branch.
  Future<List<CartSessionInfo>> listCartSessions() async {
    try {
      final response = await _dio.get('/api/v1/carts/sessions');
      final data = _extractData(response);
      final list = (data['data'] as List?) ?? const [];
      return list
          .cast<Map<String, dynamic>>()
          .map(CartSessionInfo.fromJson)
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// POST /carts/sessions/claim — claim or refresh ownership of a
  /// slot. Throws AppError(statusCode=409) when held by another
  /// user; the AppError.payload carries the holder's info.
  Future<CartSessionInfo> claimCartSession(int cartIndex) async {
    try {
      final response = await _dio.post(
        '/api/v1/carts/sessions/claim',
        data: {'cart_index': cartIndex},
      );
      final data = _extractData(response);
      return CartSessionInfo.fromJson(
          (data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// POST /carts/sessions/heartbeat — same shape as claim, called
  /// every 30s while the user stays on a tab.
  Future<CartSessionInfo> heartbeatCartSession(int cartIndex) async {
    try {
      final response = await _dio.post(
        '/api/v1/carts/sessions/heartbeat',
        data: {'cart_index': cartIndex},
      );
      final data = _extractData(response);
      return CartSessionInfo.fromJson(
          (data['data'] as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// POST /carts/sessions/release — drop the held slot. Server
  /// silently ignores release requests for slots the caller doesn't
  /// own.
  Future<void> releaseCartSession(int cartIndex) async {
    try {
      await _dio.post(
        '/api/v1/carts/sessions/release',
        data: {'cart_index': cartIndex},
      );
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  bool _isPremiumLocked(DioException error) {
    if (error.response?.statusCode != 403) return false;
    final code = _extractErrorCode(error);
    if (code == 'premium_expired' || code == 'premium_feature_locked') {
      return true;
    }
    // Canonical 2026-04-24 shape carries `error: "premium_feature_locked"`
    // at the top level instead of `error_code`.
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] == 'premium_feature_locked';
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOMERS IMPORT — Spec F026
  // ═══════════════════════════════════════════════════════════════════════════

  // Spec: specs/026-importador-clientes/spec.md
  /// Importa clientes en chunks de 100 filas.
  ///
  /// Cada chunk se envía a `POST /api/v1/customers/import` con reintentos
  /// automáticos hasta [_kImportMaxRetries] ante errores de red o 5xx.
  /// Los errores 4xx no se reintentan (AC-07 / FR-11).
  ///
  /// Retorna un [ImportReport] con los conteos acumulados de todos los chunks.
  Future<ImportReport> importCustomers(
    List<Map<String, dynamic>> rows, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (rows.isEmpty) return const ImportReport.empty();

    var aggregate = const ImportReport.empty();
    var sent = 0;

    for (var offset = 0; offset < rows.length; offset += _kImportChunkSize) {
      final end = (offset + _kImportChunkSize).clamp(0, rows.length);
      final chunk = rows.sublist(offset, end);

      final chunkReport = await _importChunkWithRetry(chunk);
      aggregate = aggregate.merge(chunkReport);
      sent += chunk.length;
      onProgress?.call(sent, rows.length);
    }

    return aggregate;
  }

  Future<ImportReport> _importChunkWithRetry(
    List<Map<String, dynamic>> chunk,
  ) async {
    DioException? lastError;
    for (var attempt = 0; attempt <= _kImportMaxRetries; attempt++) {
      try {
        final response = await _dio.post(
          '/api/v1/customers/import',
          data: {
            'rows': chunk,
            'dedup_strategy': 'merge_by_phone',
          },
        );
        final data = response.data as Map<String, dynamic>;
        return ImportReport.fromJson(data);
      } on DioException catch (e) {
        // Do not retry 4xx — the request is malformed or unauthorized.
        final status = e.response?.statusCode ?? 0;
        if (status >= 400 && status < 500) {
          throw AppError.fromDioException(e);
        }
        lastError = e;
        // Wait before retry (last attempt skips the sleep).
        if (attempt < _kImportMaxRetries &&
            attempt < _importRetryDelays.length) {
          await Future.delayed(_importRetryDelays[attempt]);
        }
      }
    }
    throw AppError.fromDioException(lastError!);
  }

  // Spec: specs/027-importador-inventario/spec.md
  /// Importa productos en chunks de 100 filas.
  ///
  /// Cada chunk se envía a `POST /api/v1/products/import` con reintentos
  /// automáticos hasta [_kImportMaxRetries] ante errores de red o 5xx.
  /// Los errores 4xx no se reintentan (FR-12).
  ///
  /// Retorna un [ImportReport] con los conteos acumulados de todos los chunks.
  /// Espejo arquitectónico de [importCustomers] (F026).
  Future<ImportReport> importProducts(
    List<Map<String, dynamic>> rows, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (rows.isEmpty) return const ImportReport.empty();

    var aggregate = const ImportReport.empty();
    var sent = 0;

    for (var offset = 0; offset < rows.length; offset += _kImportChunkSize) {
      final end = (offset + _kImportChunkSize).clamp(0, rows.length);
      final chunk = rows.sublist(offset, end);

      final chunkReport = await _importProductsChunkWithRetry(chunk);
      aggregate = aggregate.merge(chunkReport);
      sent += chunk.length;
      onProgress?.call(sent, rows.length);
    }

    return aggregate;
  }

  Future<ImportReport> _importProductsChunkWithRetry(
    List<Map<String, dynamic>> chunk,
  ) async {
    DioException? lastError;
    for (var attempt = 0; attempt <= _kImportMaxRetries; attempt++) {
      try {
        final response = await _dio.post(
          '/api/v1/products/import',
          data: {
            'rows': chunk,
            'dedup_strategy': 'merge_by_barcode_then_name',
          },
        );
        final data = response.data as Map<String, dynamic>;
        return ImportReport.fromJson(data);
      } on DioException catch (e) {
        // Do not retry 4xx — the request is malformed or unauthorized.
        final status = e.response?.statusCode ?? 0;
        if (status >= 400 && status < 500) {
          throw AppError.fromDioException(e);
        }
        lastError = e;
        // Wait before retry (last attempt skips the sleep).
        if (attempt < _kImportMaxRetries &&
            attempt < _importRetryDelays.length) {
          await Future.delayed(_importRetryDelays[attempt]);
        }
      }
    }
    throw AppError.fromDioException(lastError!);
  }

  // ─── Spec 038 — Push Notifications ────────────────────────────────

  /// Registra (o refresca, idempotente) el dispositivo contra el
  /// backend. Soporta dos modos:
  /// - **FCM** (Chrome / Firefox / Android): pasar `token`.
  /// - **Web Push nativo** (iOS Safari): pasar `endpoint` + `p256dhKey`
  ///   + `authKey`. `token` queda vacío.
  ///
  /// Al menos uno de los dos modos debe estar completo; el backend
  /// devuelve 400 si faltan ambas credenciales.
  Future<Map<String, dynamic>> registerDevice({
    String? token,
    required String platform,
    String? deviceLabel,
    String? endpoint,
    String? p256dhKey,
    String? authKey,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/devices/register',
        data: {
          if (token != null && token.isNotEmpty) 'token': token,
          'platform': platform,
          if (deviceLabel != null) 'device_label': deviceLabel,
          if (endpoint != null && endpoint.isNotEmpty) 'endpoint': endpoint,
          if (p256dhKey != null && p256dhKey.isNotEmpty)
            'p256dh_key': p256dhKey,
          if (authKey != null && authKey.isNotEmpty) 'auth_key': authKey,
        },
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Lista los dispositivos activos del usuario logueado. Lo usa la
  /// pantalla de settings para mostrar "Notificaciones activas en:
  /// iPhone Safari, Galaxy A20".
  Future<List<Map<String, dynamic>>> listMyDevices() async {
    try {
      final response = await _dio.get('/api/v1/devices/me');
      final data = response.data['data'] as List<dynamic>?;
      return (data ?? []).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Revoca (soft) un dispositivo. El token sigue válido en el
  /// browser, pero el backend lo marca `invalidated_at` y deja de
  /// enviarle push (AC-12).
  Future<void> revokeDevice(String deviceId) async {
    try {
      await _dio.delete('/api/v1/devices/me/$deviceId');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Dispara un push de prueba al tenant del usuario logueado.
  /// Retorna cuántos dispositivos recibieron la push (0 si ninguno
  /// está registrado activo). Lo usa el botón "Enviar push de
  /// prueba" en la pantalla de settings de notificaciones.
  Future<int> sendTestPush() async {
    try {
      final response = await _dio.post('/api/v1/devices/me/test');
      final data = response.data['data'] as Map<String, dynamic>?;
      return (data?['tokens_targeted'] as int?) ?? 0;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}
