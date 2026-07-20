// Spec: specs/107-dashboard-v2-resumen/spec.md
//
// Resumen del inicio v2: UNA llamada + caché local (SharedPreferences) para
// pintar sin red (Art. II). Nunca lanza: si la red falla devuelve el último
// resumen cacheado con su antigüedad; si no hay caché, un resumen vacío.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Datos del inicio. Montos en COP enteros.
class HomeSummary {
  HomeSummary({
    required this.raw,
    required this.fromCache,
    required this.ageMinutes,
  });

  final Map<String, dynamic> raw;
  final bool fromCache;
  final int ageMinutes;

  Map<String, dynamic> _m(String k) =>
      (raw[k] is Map) ? Map<String, dynamic>.from(raw[k] as Map) : const {};
  int _i(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  int get salesTotal => _i(_m('sales_today'), 'total');
  int get salesCount => _i(_m('sales_today'), 'count');
  int get profitAmount => _i(_m('profit_today'), 'amount');
  int get profitMarginPct => _i(_m('profit_today'), 'margin_pct');
  bool get shiftOpen => _m('cash_shift')['open'] == true;
  int get receivablesTotal => _i(_m('receivables'), 'total');
  int get receivablesDebtors => _i(_m('receivables'), 'debtors');
  int get receivablesOldestDays => _i(_m('receivables'), 'oldest_days');
  int get inProgressTables => _i(_m('in_progress'), 'tables');
  int get inProgressKitchen => _i(_m('in_progress'), 'kitchen');
  int get inProgressOnline => _i(_m('in_progress'), 'online');
  int get inProgressTotal =>
      inProgressTables + inProgressOnline; // cocina ⊂ mesas para el tendero
  int get lowStockCount => _i(_m('low_stock'), 'count');
  List<String> get lowStockExamples => [
        for (final e in (_m('low_stock')['examples'] as List? ?? const []))
          e.toString()
      ];
  int get tasksUrgent => _i(_m('tasks'), 'urgent');
  int get tasksActionable => _i(_m('tasks'), 'actionable');
  List<Map<String, dynamic>> get movements => [
        for (final m in (raw['movements'] as List? ?? const []))
          Map<String, dynamic>.from(m as Map)
      ];

  bool get isEmpty => raw.isEmpty;

  static HomeSummary empty() =>
      HomeSummary(raw: const {}, fromCache: false, ageMinutes: 0);
}

class HomeSummaryService {
  HomeSummaryService({required this.fetch, this.persist = true});

  /// Inyección para tests: en producción, `api.fetchDashboardSummary`.
  final Future<Map<String, dynamic>> Function() fetch;
  final bool persist;

  static const prefsKey = 'vendia:home:summary';
  static const prefsAtKey = 'vendia:home:summary_at';

  /// Nunca lanza: red → fresco; error → caché; sin caché → vacío.
  Future<HomeSummary> load() async {
    try {
      final data = await fetch();
      if (persist) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(prefsKey, jsonEncode(data));
          await prefs.setInt(
              prefsAtKey, DateTime.now().millisecondsSinceEpoch);
        } catch (_) {}
      }
      return HomeSummary(raw: data, fromCache: false, ageMinutes: 0);
    } catch (_) {
      return _fromCache();
    }
  }

  Future<HomeSummary> _fromCache() async {
    if (!persist) return HomeSummary.empty();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return HomeSummary.empty();
      final at = prefs.getInt(prefsAtKey) ?? 0;
      final age = at == 0
          ? 0
          : DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(at))
              .inMinutes;
      return HomeSummary(
        raw: Map<String, dynamic>.from(jsonDecode(raw) as Map),
        fromCache: true,
        ageMinutes: age,
      );
    } catch (_) {
      return HomeSummary.empty();
    }
  }
}

/// Formatea COP enteros con punto de miles: 486500 → "486.500".
String formatCopHome(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}
