import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_upsell_sheet.dart';
import 'app_error.dart';
import 'auth_service.dart';

/// Central API client for the VendIA backend.
/// Integrates with the full contract: 18 modules, 70+ endpoints.
/// All protected endpoints auto-inject JWT via interceptor.
class ApiService {
  late final Dio _dio;
  final AuthService _auth;

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

  ApiService(this._auth) {
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
                  Icon(Icons.lock_clock_rounded,
                      color: Colors.white, size: 24),
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
  }

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

  /// Select a workspace (multi-workspace flow). Requires temp_token as auth.
  Future<Map<String, dynamic>> selectWorkspace({
    required String workspaceId,
    required String tempToken,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/select-workspace',
        data: {'workspace_id': workspaceId},
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
  Future<Map<String, dynamic>> createBranch(
      Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/store/branches', data: data);
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

  Future<Map<String, dynamic>> createEmployee(
      Map<String, dynamic> data) async {
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
      final response =
          await _dio.patch('/api/v1/employees/$uuid', data: data);
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
      final response = await _dio.get('/api/v1/products',
          queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createProduct(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/products', data: data);
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
      final response = await _dio.get('/api/v1/catalog/search',
          queryParameters: {'q': query});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> searchProductsOFF(String query) async {
    try {
      final response = await _dio.get('/api/v1/products/search-off',
          queryParameters: {'q': query});
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

  Future<Map<String, dynamic>> uploadProductPhoto(
      String uuid, File photo) async {
    try {
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(photo.path),
      });
      final response = await _dio.post('/api/v1/products/$uuid/photo',
          data: formData);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> enhanceProductPhoto(String uuid, {
    String? name, String? presentation, String? content,
  }) async {
    try {
      final params = <String, String>{};
      if (name != null && name.isNotEmpty) params['name'] = name;
      if (presentation != null && presentation.isNotEmpty) params['presentation'] = presentation;
      if (content != null && content.isNotEmpty) params['content'] = content;
      final response = await _dio.post(
        '/api/v1/products/$uuid/enhance',
        queryParameters: params.isEmpty ? null : params,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> generateProductImage(String uuid, {
    String? name, String? presentation, String? content,
  }) async {
    try {
      final params = <String, String>{};
      if (name != null && name.isNotEmpty) params['name'] = name;
      if (presentation != null && presentation.isNotEmpty) params['presentation'] = presentation;
      if (content != null && content.isNotEmpty) params['content'] = content;
      final response = await _dio.post(
        '/api/v1/products/$uuid/generate-image',
        queryParameters: params.isEmpty ? null : params,
      );
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
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

  /// Phase-4 Voice-to-Catalog: ships the tendero's recorded note to
  /// Gemini multimodal and returns the parsed `[{name, quantity,
  /// price}]` array. The backend gates the endpoint behind
  /// PremiumAuth — an expired trial returns 403 premium_expired and
  /// bubbles up through the existing soft-paywall interceptor.
  Future<List<Map<String, dynamic>>> voiceInventory({
    required File audioFile,
    required String mimeType,
  }) async {
    try {
      final fields = <String, dynamic>{
        'audio_file': await MultipartFile.fromFile(
          audioFile.path,
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

  Future<List<Map<String, dynamic>>> fetchInventoryAlerts() async {
    try {
      final response = await _dio.get('/api/v1/inventory/alerts');
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

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. SALES (POS)
  // ═══════════════════════════════════════════════════════════════════════════

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
      final response = await _dio.get('/api/v1/sales',
          queryParameters: params);
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
    String? query,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (date != null) params['date'] = date;
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

  Future<Map<String, dynamic>> createCustomer(
      Map<String, dynamic> data) async {
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
      final response =
          await _dio.post('/api/v1/fiar/remind/$customerUuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. ORDERS / KDS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> createOrder(
      Map<String, dynamic> data) async {
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

  Future<Map<String, dynamic>> updateOrderStatus(
      String uuid, String status,
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

  Future<Map<String, dynamic>> createSupplier(
      Map<String, dynamic> data) async {
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
      final response =
          await _dio.patch('/api/v1/suppliers/$uuid', data: data);
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
      final response =
          await _dio.post('/api/v1/suppliers/$supplierUuid/order-wa',
              data: data);
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

  Future<Map<String, dynamic>> createRecipe(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/api/v1/recipes', data: data);
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

  Future<Map<String, dynamic>> applyPromotionToPOS(
      String promotionUuid) async {
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
      final response =
          await _dio.get('/api/v1/store/$slug/product/$uuid');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Public — no auth required
  Future<Map<String, dynamic>> createWebOrder(
      String slug, Map<String, dynamic> data) async {
    try {
      final response =
          await _dio.post('/api/v1/store/$slug/order', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Public — no auth required
  Future<Map<String, dynamic>> fetchWebOrderStatus(
      String slug, String uuid) async {
    try {
      final response =
          await _dio.get('/api/v1/store/$slug/order/$uuid');
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

  Future<Map<String, dynamic>> fetchAnalyticsDashboard() async {
    try {
      final response = await _dio.get('/api/v1/analytics/dashboard');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchTopProducts(
      {String period = '7d'}) async {
    try {
      final response = await _dio.get('/api/v1/analytics/top-products',
          queryParameters: {'period': period});
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchPhotoCoverage() async {
    try {
      final response = await _dio.get('/api/v1/analytics/photo-coverage');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchSalesByEmployee() async {
    try {
      final response =
          await _dio.get('/api/v1/analytics/sales-by-employee');
      return _extractList(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchInventoryHealth() async {
    try {
      final response =
          await _dio.get('/api/v1/analytics/inventory-health');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchIngestionMethod() async {
    try {
      final response =
          await _dio.get('/api/v1/analytics/ingestion-method');
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

  Future<Map<String, dynamic>> generateLogoAI({
    required String businessName,
    required String businessType,
  }) async {
    try {
      final response = await _dio.post('/api/v1/tenant/generate-logo', data: {
        'business_name': businessName,
        'business_type': businessType,
      });
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> uploadLogo(File logo) async {
    try {
      final formData = FormData.fromMap({
        'logo': await MultipartFile.fromFile(logo.path),
      });
      final response =
          await _dio.post('/api/v1/tenant/upload-logo', data: formData);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
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

  Future<Map<String, dynamic>> fetchAccountRealTime(
      String orderUuid) async {
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
      final response = await _dio.post(
          '/api/v1/orders/$orderUuid/payments',
          data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchOrderPayments(String orderUuid) async {
    try {
      final response =
          await _dio.get('/api/v1/orders/$orderUuid/payments');
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> registerSplitPayments(
      String orderUuid, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
          '/api/v1/orders/$orderUuid/split-payments',
          data: data);
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
        queryParameters: {'period': period},
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
        queryParameters: {'period': period, 'page': page, 'per_page': perPage},
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

  Future<void> updatePanicMessage(String? message, {
    bool? includeAddress,
    bool? includeGPS,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (message != null) data['panic_message'] = message;
      if (includeAddress != null) data['panic_include_address'] = includeAddress;
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

  Future<Map<String, dynamic>> registerAbono(String creditId, {
    required int amount,
    String method = 'cash',
    String note = '',
  }) async {
    try {
      final response = await _dio.post('/api/v1/credits/$creditId/payments',
          data: {'amount': amount, 'payment_method': method, 'note': note});
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Append an amount to an already-accepted open fiado. Skips the WhatsApp
  /// handshake — the owner already authorized this line of credit when the
  /// customer originally accepted it.
  Future<Map<String, dynamic>> appendToFiado(String creditId, {
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
  Future<Map<String, dynamic>> closeFiado(String creditId, {
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
  Future<Map<String, dynamic>> cancelFiado(String creditId, {
    String reason = '',
  }) async {
    try {
      final response = await _dio.post('/api/v1/credits/$creditId/cancel',
          data: {'reason': reason});
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
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/orders/partial-payments',
        data: {
          'order_id': orderId,
          'amount': amount,
          'payment_method': paymentMethod,
          'payment_method_id': paymentMethodId,
          'notes': notes,
        },
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
  /// Returns false on wrong PIN or if the owner has not yet set one.
  Future<bool> verifyOwnerPin(String pin) async {
    try {
      final resp = await _dio.post(
        '/api/v1/tenant/owner-pin/verify',
        data: {'pin': pin},
      );
      final body = resp.data;
      if (body is Map && body['ok'] == true) return true;
      return false;
    } on DioException {
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
}

