import 'package:dio/dio.dart';
import 'auth_service.dart';

// ── Modelos ────────────────────────────────────────────────────────────────────

class DashboardStats {
  final double totalSalesToday;
  final int transactionCount;
  final String topProduct;
  final String trend;

  const DashboardStats({
    required this.totalSalesToday,
    required this.transactionCount,
    required this.topProduct,
    required this.trend,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalSalesToday: (json['total_sales_today'] as num? ?? 0).toDouble(),
      transactionCount: json['transaction_count'] as int? ?? 0,
      topProduct: json['top_product'] as String? ?? '—',
      trend: json['trend'] as String? ?? '+0%',
    );
  }

  /// Formato peso colombiano: $5.900
  String get formattedTotal => _formatCOP(totalSalesToday);
}

class RecentSale {
  final int id;
  final double total;
  final String paymentMethod;
  final DateTime createdAt;
  final List<SaleItemSnap> items;

  const RecentSale({
    required this.id,
    required this.total,
    required this.paymentMethod,
    required this.createdAt,
    required this.items,
  });

  factory RecentSale.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return RecentSale(
      id: json['id'] as int,
      total: (json['total'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      createdAt: DateTime.parse(json['created_at'] as String),
      items: rawItems
          .map((e) => SaleItemSnap.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Descripción corta para la lista: "Coca-Cola 400ml + 2 más"
  String get label {
    if (items.isEmpty) return 'Venta #$id';
    if (items.length == 1) {
      return items.first.quantity > 1
          ? '${items.first.name} x${items.first.quantity}'
          : items.first.name;
    }
    return '${items.first.name} + ${items.length - 1} más';
  }

  String get formattedTotal => _formatCOP(total);

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} día${diff.inDays > 1 ? 's' : ''}';
  }
}

class SaleItemSnap {
  final String name;
  final int quantity;
  final double price;

  const SaleItemSnap(
      {required this.name, required this.quantity, required this.price});

  factory SaleItemSnap.fromJson(Map<String, dynamic> json) {
    return SaleItemSnap(
      name: json['name'] as String,
      quantity: json['quantity'] as int,
      price: (json['price'] as num).toDouble(),
    );
  }
}

// ── Servicio ───────────────────────────────────────────────────────────────────

class DashboardService {
  final Dio _dio;
  final AuthService _auth;

  DashboardService(this._dio, this._auth);

  Future<Options> get _authOpts async {
    final token = await _auth.getToken();
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<DashboardStats> fetchStats() async {
    final res = await _dio.get('/api/v1/sales/today', options: await _authOpts);
    return DashboardStats.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<RecentSale>> fetchRecentSales() async {
    final res = await _dio.get('/api/v1/sales', options: await _authOpts);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => RecentSale.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ── Utilidad de formato ────────────────────────────────────────────────────────

String _formatCOP(double amount) {
  final int cents = amount.round();
  if (cents == 0) return '\$0';
  final String s = cents.toString();
  final buffer = StringBuffer('\$');
  final start = s.length % 3;
  if (start > 0) buffer.write(s.substring(0, start));
  for (int i = start; i < s.length; i += 3) {
    if (i > 0) buffer.write('.');
    buffer.write(s.substring(i, i + 3));
  }
  return buffer.toString();
}
