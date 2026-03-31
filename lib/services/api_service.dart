import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../theme/app_theme.dart';
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
        final needsAuth = options.path.startsWith('/api/v1') &&
            !options.path.contains('/store/') &&
            !options.path.contains('/account/') &&
            !options.path.contains('/rockola/') ||
            options.path.contains('/api/v1/store/config') ||
            options.path.contains('/api/v1/rockola/pending') ||
            options.path.contains('/api/v1/rockola/search');

        if (needsAuth || options.path == '/api/v1/auth/logout') {
          final token = await _auth.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
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
  // 2. EMPLOYEES
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
  }) async {
    try {
      final response = await _dio.get('/api/v1/products',
          queryParameters: {'page': page, 'per_page': perPage});
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

  Future<Map<String, dynamic>> lookupBarcode(String barcode) async {
    try {
      final response = await _dio.get('/api/v1/products/lookup',
          queryParameters: {'barcode': barcode});
      return _extractData(response);
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

  Future<Map<String, dynamic>> enhanceProductPhoto(String uuid) async {
    try {
      final response = await _dio.post('/api/v1/products/$uuid/enhance');
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
      final response = await _dio.post('/api/v1/sales', data: data);
      return _extractData(response);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> fetchSales({
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get('/api/v1/sales',
          queryParameters: {'page': page, 'per_page': perPage});
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
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (status != null) params['status'] = status;
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
  // 15. LOGO IA
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> generateLogo() async {
    try {
      final response = await _dio.post('/api/v1/tenant/generate-logo');
      return _extractList(response);
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
}
