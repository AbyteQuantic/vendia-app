import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/sync/sales_sync.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Owner / manager dashboard. Pulls a single comprehensive endpoint
/// (`/analytics/financial-summary`) that returns the full cube and
/// renders it as a stack of focused sections so the tendero can scan
/// the screen and decide:
///
///   1. Hero KPIs                — total ventas, ticket prom, vs período anterior
///   2. Cash flow                — efectivo / digital / fiado / utilidad
///   3. Por canal                — POS / Mesa / Online
///   4. Por método de pago
///   5. Hora pico + primera venta
///   6. Mejor / peor día (semana / mes)
///   7. Ranking de empleados con ganancia estimada
///   8. Historial de ventas
///
/// Filters live in a bottom sheet: rango (Hoy/Semana/Mes), empleado,
/// canal, método de pago. Server is the source of truth; offline we
/// fall back to a "Sin datos" empty state instead of stale local Isar
/// (the previous implementation overlaid local data and showed $0
/// when the cashier's sale lived only on her device — that bug went
/// away once the backend became authoritative).
class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  State<FinancialDashboardScreen> createState() =>
      _FinancialDashboardScreenState();
}

enum _Period { today, week, month }

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  late final ApiService _api;

  _Period _period = _Period.today;
  String? _employeeFilter;
  String? _sourceFilter;
  String? _methodFilter;

  bool _loading = true;
  String? _errorMsg;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _pushThenLoad();
  }

  /// Push any unsynced local sales FIRST, then load the financial
  /// summary from the server. This ensures sales made offline or
  /// not yet synced appear in the dashboard.
  Future<void> _pushThenLoad() async {
    try {
      await SalesSyncService.pushToServer();
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final data = await _api.fetchFinancialSummaryFull(
        period: _period.name,
        employee: _employeeFilter,
        source: _sourceFilter,
        paymentMethod: _methodFilter,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'No se pudo cargar el panel: $e';
        _loading = false;
      });
    }
  }

  void _setPeriod(_Period p) {
    if (_period == p) return;
    HapticFeedback.lightImpact();
    setState(() => _period = p);
    _load();
  }

  Future<void> _openFilters() async {
    final available = (_data?['available_employees'] as List?)
            ?.cast<String>()
            .toList() ??
        const <String>[];
    final result = await showModalBottomSheet<_FilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _FilterSheet(
        availableEmployees: available,
        initialEmployee: _employeeFilter,
        initialSource: _sourceFilter,
        initialMethod: _methodFilter,
      ),
    );
    if (result == null) return;
    setState(() {
      _employeeFilter = result.employee;
      _sourceFilter = result.source;
      _methodFilter = result.method;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Finanzas',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            icon: Stack(
              children: [
                const Icon(Icons.tune_rounded, size: 26),
                if (_hasActiveFilter)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _pushThenLoad,
        color: AppTheme.primary,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMsg != null
                ? _ErrorState(message: _errorMsg!, onRetry: _load)
                : _buildBody(),
      ),
    );
  }

  bool get _hasActiveFilter =>
      (_employeeFilter ?? '').isNotEmpty ||
      (_sourceFilter ?? '').isNotEmpty ||
      (_methodFilter ?? '').isNotEmpty;

  Widget _buildBody() {
    final d = _data ?? const {};
    final totalSales = (d['total_sales'] as num?)?.toDouble() ?? 0;
    final txCount = (d['transaction_count'] as num?)?.toInt() ?? 0;
    final avgTicket = (d['avg_ticket'] as num?)?.toDouble() ?? 0;
    final vsPrev = (d['vs_previous_pct'] as num?)?.toDouble();
    final cash = (d['cash_in_drawer'] as num?)?.toDouble() ?? 0;
    final digital = (d['digital_money'] as num?)?.toDouble() ?? 0;
    final fiado = (d['credit_paid_total'] as num?)?.toDouble() ?? 0;
    final receivable = (d['accounts_receivable'] as num?)?.toDouble() ?? 0;
    final profit = (d['total_profit'] as num?)?.toDouble() ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _PeriodChips(period: _period, onChanged: _setPeriod),
        if (_hasActiveFilter) ...[
          const SizedBox(height: 8),
          _ActiveFiltersBar(
            employee: _employeeFilter,
            source: _sourceFilter,
            method: _methodFilter,
            onClear: () {
              setState(() {
                _employeeFilter = null;
                _sourceFilter = null;
                _methodFilter = null;
              });
              _load();
            },
          ),
        ],
        const SizedBox(height: 12),
        _HeroKpi(
          total: totalSales,
          txCount: txCount,
          avgTicket: avgTicket,
          vsPrevPct: vsPrev,
        ),
        const SizedBox(height: 12),
        _CashFlowCards(
            cash: cash, digital: digital, fiado: fiado, profit: profit),
        const SizedBox(height: 12),
        _ReceivablePill(amount: receivable),
        const SizedBox(height: 18),
        _Section(
          icon: Icons.pie_chart_outline_rounded,
          title: 'Por canal de venta',
          child: _BreakdownBars(
            rows: ((d['by_channel'] as List?) ?? const [])
                .cast<Map>()
                .map((m) => _BarRow(
                      label: _channelLabel(m['source']?.toString() ?? ''),
                      total: (m['total'] as num?)?.toDouble() ?? 0,
                      count: (m['count'] as num?)?.toInt() ?? 0,
                      color: _channelColor(m['source']?.toString() ?? ''),
                    ))
                .toList(),
            grandTotal: totalSales,
          ),
        ),
        _Section(
          icon: Icons.payments_outlined,
          title: 'Por método de pago',
          child: _BreakdownBars(
            rows: ((d['by_method'] as List?) ?? const [])
                .cast<Map>()
                .map((m) => _BarRow(
                      label: _methodLabel(
                          m['payment_method']?.toString() ?? ''),
                      total: (m['total'] as num?)?.toDouble() ?? 0,
                      count: (m['count'] as num?)?.toInt() ?? 0,
                      color: _methodColor(
                          m['payment_method']?.toString() ?? ''),
                    ))
                .toList(),
            grandTotal: totalSales,
          ),
        ),
        _Section(
          icon: Icons.access_time_rounded,
          title: 'Hora del día',
          child: _HourHeatmap(
            byHour: ((d['by_hour'] as List?) ?? const [])
                .cast<Map>()
                .toList(),
            firstSaleAt: d['first_sale_at']?.toString(),
            peakHour: d['peak_hour'] as Map?,
          ),
        ),
        if (_period != _Period.today)
          _Section(
            icon: Icons.calendar_view_week_rounded,
            title: 'Día de la semana',
            child: _WeekdayBars(
              byWeekday: ((d['by_weekday'] as List?) ?? const [])
                  .cast<Map>()
                  .toList(),
              best: d['best_day'] as Map?,
              worst: d['worst_day'] as Map?,
            ),
          ),
        _Section(
          icon: Icons.emoji_events_outlined,
          title: 'Ranking del equipo',
          child: _EmployeeLeaderboard(
            rows: ((d['top_employees'] as List?) ?? const [])
                .cast<Map>()
                .toList(),
          ),
        ),
        // Sales history at the bottom — every transaction in the
        // window with WHO sold it (employee), WHEN, HOW (method),
        // WHAT (first item + count). Filters carry over from the
        // top-of-screen filter sheet.
        _SalesHistorySection(
          period: _period.name,
          employee: _employeeFilter,
          source: _sourceFilter,
          paymentMethod: _methodFilter,
        ),
      ],
    );
  }
}

/// Streams the period sales straight from the backend so the owner
/// sees attribution (employee_name) without depending on local Isar.
/// Lives at the bottom of the Finanzas screen and re-fetches whenever
/// any of the upstream filters change (period / employee / channel /
/// method).
class _SalesHistorySection extends StatefulWidget {
  final String period;
  final String? employee;
  final String? source;
  final String? paymentMethod;
  const _SalesHistorySection({
    required this.period,
    required this.employee,
    required this.source,
    required this.paymentMethod,
  });

  @override
  State<_SalesHistorySection> createState() => _SalesHistorySectionState();
}

class _SalesHistorySectionState extends State<_SalesHistorySection> {
  late final ApiService _api;
  bool _loading = true;
  List<dynamic> _sales = const [];

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  @override
  void didUpdateWidget(_SalesHistorySection old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period ||
        old.employee != widget.employee ||
        old.source != widget.source ||
        old.paymentMethod != widget.paymentMethod) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.fetchSalesHistoryByPeriod(
        period: widget.period,
        page: 1,
        perPage: 50,
      );
      if (!mounted) return;
      setState(() {
        // Filter client-side using the same predicates as the dashboard
        // — saves a backend roundtrip and keeps the source of truth one
        // endpoint until SalesHistoryByPeriod grows the same filters.
        _sales = list.where((s) {
          if (widget.employee != null && widget.employee!.isNotEmpty) {
            if ((s['employee_name'] ?? '') != widget.employee) return false;
          }
          if (widget.source != null && widget.source!.isNotEmpty) {
            if ((s['source'] ?? '') != widget.source) return false;
          }
          if (widget.paymentMethod != null &&
              widget.paymentMethod!.isNotEmpty) {
            if ((s['payment_method'] ?? '') != widget.paymentMethod) {
              return false;
            }
          }
          return true;
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sales = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      icon: Icons.receipt_long_rounded,
      title: 'Historial de ventas',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          : _sales.isEmpty
              ? const Text('No hay ventas en este período.',
                  style: TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary))
              : Column(
                  children: _sales
                      .take(20)
                      .map((s) => _SaleTile(s as Map<String, dynamic>))
                      .toList(),
                ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final Map<String, dynamic> sale;
  const _SaleTile(this.sale);

  @override
  Widget build(BuildContext context) {
    final total = (sale['total'] as num?)?.toDouble() ?? 0;
    final method = (sale['payment_method'] ?? '') as String;
    final source = (sale['source'] ?? 'POS') as String;
    final employee = (sale['employee_name'] ?? '') as String;
    final createdAt = DateTime.tryParse(sale['created_at']?.toString() ?? '')
            ?.toLocal() ??
        DateTime.now();
    final items = (sale['Items'] ?? sale['items'] ?? const []) as List;
    String label = 'Venta';
    if (items.isNotEmpty) {
      final first = items.first as Map;
      label = (first['name'] ?? first['product_name'] ?? 'Producto') as String;
      if (items.length > 1) {
        label = '$label + ${items.length - 1} más';
      }
    }
    final timeStr =
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _methodColor(method).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_methodIcon(method),
                size: 20, color: _methodColor(method)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${employee.isEmpty ? "Sin asignar" : employee} · '
                  '$timeStr · '
                  '${_methodLabel(method)} · '
                  '${_channelLabel(source)}',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_formatMoney(total),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _methodColor(method))),
        ],
      ),
    );
  }
}

IconData _methodIcon(String m) => switch (m) {
      'cash' => Icons.payments_rounded,
      'transfer' || 'nequi' || 'daviplata' => Icons.phone_android_rounded,
      'card' => Icons.credit_card_rounded,
      'credit' => Icons.menu_book_rounded,
      _ => Icons.receipt_rounded,
    };

// ── Helpers ────────────────────────────────────────────────────────

String _channelLabel(String s) => switch (s) {
      'POS' => 'Mostrador',
      'TABLE' => 'Mesa',
      'WEB' => 'Tienda online',
      _ => s.isEmpty ? 'Otro' : s,
    };

Color _channelColor(String s) => switch (s) {
      'POS' => AppTheme.primary,
      'TABLE' => const Color(0xFFEA580C),
      'WEB' => const Color(0xFF7C3AED),
      _ => Colors.grey,
    };

String _methodLabel(String m) => switch (m) {
      'cash' => 'Efectivo',
      'transfer' => 'Transferencia',
      'card' => 'Tarjeta',
      'nequi' => 'Nequi',
      'daviplata' => 'Daviplata',
      'credit' => 'Fiado',
      _ => m,
    };

Color _methodColor(String m) => switch (m) {
      'cash' => AppTheme.success,
      'transfer' || 'nequi' || 'daviplata' || 'card' => AppTheme.primary,
      'credit' => AppTheme.warning,
      _ => Colors.grey,
    };

String _formatMoney(double amount) {
  final cents = amount.round();
  if (cents == 0) return r'$0';
  final s = cents.abs().toString();
  final buf = StringBuffer(cents < 0 ? r'-$' : r'$');
  final start = s.length % 3;
  if (start > 0) buf.write(s.substring(0, start));
  for (int i = start; i < s.length; i += 3) {
    if (i > 0) buf.write('.');
    buf.write(s.substring(i, i + 3));
  }
  return buf.toString();
}

// ── Layout pieces ──────────────────────────────────────────────────

class _PeriodChips extends StatelessWidget {
  final _Period period;
  final ValueChanged<_Period> onChanged;
  const _PeriodChips({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _Period.values.map((p) {
        final active = p == period;
        return ChoiceChip(
          label: Text(switch (p) {
            _Period.today => 'Hoy',
            _Period.week => '7 días',
            _Period.month => '30 días',
          }),
          labelStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppTheme.textPrimary,
          ),
          selected: active,
          selectedColor: AppTheme.primary,
          backgroundColor: AppTheme.surfaceGrey,
          onSelected: (_) => onChanged(p),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color:
                      active ? AppTheme.primary : AppTheme.borderColor)),
        );
      }).toList(),
    );
  }
}

class _ActiveFiltersBar extends StatelessWidget {
  final String? employee;
  final String? source;
  final String? method;
  final VoidCallback onClear;
  const _ActiveFiltersBar({
    required this.employee,
    required this.source,
    required this.method,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if ((employee ?? '').isNotEmpty) chips.add(_pill('👤 $employee'));
    if ((source ?? '').isNotEmpty) chips.add(_pill('📍 ${_channelLabel(source!)}'));
    if ((method ?? '').isNotEmpty) chips.add(_pill('💳 ${_methodLabel(method!)}'));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...chips,
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Quitar filtros'),
          style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10)),
        ),
      ],
    );
  }

  Widget _pill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary)),
      );
}

class _HeroKpi extends StatelessWidget {
  final double total;
  final int txCount;
  final double avgTicket;
  final double? vsPrevPct;
  const _HeroKpi({
    required this.total,
    required this.txCount,
    required this.avgTicket,
    required this.vsPrevPct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, Color(0xFF3D5AFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.show_chart_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Ventas del período',
                style: TextStyle(fontSize: 16, color: Colors.white)),
          ]),
          const SizedBox(height: 6),
          Text(_formatMoney(total),
              style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.1)),
          const SizedBox(height: 6),
          Row(children: [
            Text('$txCount transacciones',
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.85))),
            if (txCount > 0) ...[
              const Text(' · ',
                  style: TextStyle(color: Colors.white70, fontSize: 15)),
              Text('Ticket prom. ${_formatMoney(avgTicket)}',
                  style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.85))),
            ],
          ]),
          if (vsPrevPct != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                vsPrevPct! >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: vsPrevPct! >= 0
                    ? const Color(0xFF6EE7B7)
                    : const Color(0xFFFCA5A5),
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                '${vsPrevPct! >= 0 ? '+' : ''}${vsPrevPct!.toStringAsFixed(1)}% vs período anterior',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _CashFlowCards extends StatelessWidget {
  final double cash, digital, fiado, profit;
  const _CashFlowCards({
    required this.cash,
    required this.digital,
    required this.fiado,
    required this.profit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: _MoneyCard(
            label: 'Efectivo',
            amount: cash,
            color: AppTheme.success,
            icon: Icons.payments_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MoneyCard(
            label: 'Dinero digital',
            amount: digital,
            color: AppTheme.primary,
            icon: Icons.phone_android_rounded,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _MoneyCard(
            label: 'Fiado del período',
            amount: fiado,
            color: AppTheme.warning,
            icon: Icons.menu_book_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MoneyCard(
            label: 'Utilidad estimada',
            amount: profit,
            color: const Color(0xFF7C3AED),
            icon: Icons.show_chart_rounded,
          ),
        ),
      ]),
    ]);
  }
}

class _MoneyCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  const _MoneyCard(
      {required this.label,
      required this.amount,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_formatMoney(amount),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _ReceivablePill extends StatelessWidget {
  final double amount;
  const _ReceivablePill({required this.amount});

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_rounded,
              color: AppTheme.warning, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Total cuentas por cobrar (todos los fiados abiertos)',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
          ),
          Text(_formatMoney(amount),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.warning)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _Section(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BarRow {
  final String label;
  final double total;
  final int count;
  final Color color;
  _BarRow({
    required this.label,
    required this.total,
    required this.count,
    required this.color,
  });
}

class _BreakdownBars extends StatelessWidget {
  final List<_BarRow> rows;
  final double grandTotal;
  const _BreakdownBars({required this.rows, required this.grandTotal});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || grandTotal <= 0) {
      return const Text('Sin datos en este período.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSecondary));
    }
    rows.sort((a, b) => b.total.compareTo(a.total));
    return Column(
      children: rows.map((r) {
        final share = grandTotal > 0 ? r.total / grandTotal : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(r.label,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary))),
                Text(_formatMoney(r.total),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: r.color)),
                const SizedBox(width: 6),
                Text('${(share * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: share.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: AppTheme.surfaceGrey,
                  valueColor: AlwaysStoppedAnimation(r.color),
                ),
              ),
              const SizedBox(height: 2),
              Text('${r.count} transacciones',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _HourHeatmap extends StatelessWidget {
  final List<Map> byHour;
  final String? firstSaleAt;
  final Map? peakHour;
  const _HourHeatmap(
      {required this.byHour,
      required this.firstSaleAt,
      required this.peakHour});

  static String _fmtHour(int h) {
    if (h == 0) return '12 am';
    if (h < 12) return '$h am';
    if (h == 12) return '12 pm';
    return '${h - 12} pm';
  }

  static String _fmtCOP(double v) {
    final s = v.round().toString();
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (byHour.isEmpty) {
      return const Text('Sin ventas en este período.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSecondary));
    }

    // Build sorted list of hours with sales only
    final entries = <({int hour, double total, int count})>[];
    for (final h in byHour) {
      final hour = (h['hour'] as num?)?.toInt() ?? 0;
      final total = (h['total'] as num?)?.toDouble() ?? 0;
      final count = (h['count'] as num?)?.toInt() ?? 0;
      if (total > 0) entries.add((hour: hour, total: total, count: count));
    }
    entries.sort((a, b) => a.hour.compareTo(b.hour));
    // First sale time
    String firstStr = '—';
    if (firstSaleAt != null) {
      final dt = DateTime.tryParse(firstSaleAt!)?.toLocal();
      if (dt != null) {
        firstStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    final peakH = (peakHour?['hour'] as num?)?.toInt();
    final peakShare = (peakHour?['share_pct'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats row
        Row(children: [
          Expanded(
            child: _MiniStat(
                label: 'Primera venta',
                value: firstStr,
                color: AppTheme.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniStat(
                label: 'Hora pico',
                value: peakH == null
                    ? '—'
                    : '${_fmtHour(peakH)} · ${peakShare.toStringAsFixed(0)}%',
                color: AppTheme.primary),
          ),
        ]),
        const SizedBox(height: 16),

        // Simple table: hour | count | amount
        if (entries.isEmpty)
          const Text('Sin datos por hora.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary))
        else
          ...entries.map((e) {
            final isPeak = e.hour == peakH;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      _fmtHour(e.hour),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isPeak ? FontWeight.w800 : FontWeight.w500,
                        color: isPeak ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPeak
                          ? AppTheme.primary.withValues(alpha: 0.12)
                          : AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${e.count} venta${e.count > 1 ? "s" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isPeak ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _fmtCOP(e.total),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isPeak ? AppTheme.primary : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _WeekdayBars extends StatelessWidget {
  final List<Map> byWeekday;
  final Map? best;
  final Map? worst;
  const _WeekdayBars(
      {required this.byWeekday, required this.best, required this.worst});

  static const _fullNames = [
    'Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb',
  ];

  @override
  Widget build(BuildContext context) {
    if (byWeekday.isEmpty) {
      return const Text('Sin datos en este período.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSecondary));
    }
    final byMap = <int, double>{
      for (final w in byWeekday)
        ((w['weekday'] as num?)?.toInt() ?? 0):
            ((w['total'] as num?)?.toDouble() ?? 0)
    };
    final max = byMap.values.fold<double>(0, (a, b) => b > a ? b : a);
    final bestDay = (best?['weekday'] as num?)?.toInt();
    final worstDay = (worst?['weekday'] as num?)?.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (best != null)
          _DayHighlight(
              label: 'Mejor día',
              dayName: best?['name']?.toString() ?? '',
              total: (best?['total'] as num?)?.toDouble() ?? 0,
              color: AppTheme.success),
        if (worst != null)
          _DayHighlight(
              label: 'Peor día',
              dayName: worst?['name']?.toString() ?? '',
              total: (worst?['total'] as num?)?.toDouble() ?? 0,
              color: AppTheme.error),
        const SizedBox(height: 14),
        // Horizontal bars — one per day, no overflow
        ...List.generate(7, (dow) {
          final v = byMap[dow] ?? 0;
          final ratio = max > 0 ? v / max : 0.0;
          final isBest = dow == bestDay;
          final isWorst = dow == worstDay && !isBest;
          final barColor = isBest
              ? AppTheme.success
              : isWorst
                  ? AppTheme.error
                  : AppTheme.primary;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    _fullNames[dow],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (isBest || isWorst)
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: (isBest || isWorst)
                          ? barColor
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0, 1).toDouble(),
                      minHeight: 14,
                      backgroundColor: AppTheme.surfaceGrey,
                      valueColor: AlwaysStoppedAnimation(
                        barColor.withValues(alpha: v > 0 ? 0.7 : 0.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    v > 0 ? _formatMoney(v) : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: v > 0 ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _DayHighlight extends StatelessWidget {
  final String label;
  final String dayName;
  final double total;
  final Color color;
  const _DayHighlight(
      {required this.label,
      required this.dayName,
      required this.total,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(dayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Text(_formatMoney(total),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

class _EmployeeLeaderboard extends StatelessWidget {
  final List<Map> rows;
  const _EmployeeLeaderboard({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('Aún no hay ventas registradas.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSecondary));
    }
    return Column(
      children: rows.asMap().entries.map((e) {
        final idx = e.key;
        final r = e.value;
        final name = (r['name'] ?? '') as String;
        final sales = (r['sales_total'] as num?)?.toDouble() ?? 0;
        final tx = (r['tx_count'] as num?)?.toInt() ?? 0;
        final profit = (r['profit'] as num?)?.toDouble() ?? 0;
        final medal = idx == 0
            ? '🥇'
            : idx == 1
                ? '🥈'
                : idx == 2
                    ? '🥉'
                    : '#${idx + 1}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Text(medal,
                  style:
                      const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                      '$tx ${tx == 1 ? 'venta' : 'ventas'} · Ganancia ${_formatMoney(profit)}',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Text(_formatMoney(sales),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary)),
          ]),
        );
      }).toList(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_rounded,
            size: 56, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
        const SizedBox(height: 18),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

// ── Filter sheet ───────────────────────────────────────────────────

class _FilterSelection {
  final String? employee;
  final String? source;
  final String? method;
  const _FilterSelection({this.employee, this.source, this.method});
}

class _FilterSheet extends StatefulWidget {
  final List<String> availableEmployees;
  final String? initialEmployee;
  final String? initialSource;
  final String? initialMethod;
  const _FilterSheet({
    required this.availableEmployees,
    required this.initialEmployee,
    required this.initialSource,
    required this.initialMethod,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _employee;
  late String? _source;
  late String? _method;

  @override
  void initState() {
    super.initState();
    _employee = widget.initialEmployee;
    _source = widget.initialSource;
    _method = widget.initialMethod;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Filtrar el panel',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (widget.availableEmployees.isNotEmpty) ...[
            const Text('Empleado',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _ChipChoice(
                  label: 'Todos',
                  selected: _employee == null,
                  onTap: () => setState(() => _employee = null),
                ),
                ...widget.availableEmployees.map((e) => _ChipChoice(
                      label: e,
                      selected: _employee == e,
                      onTap: () => setState(() => _employee = e),
                    )),
              ],
            ),
            const SizedBox(height: 14),
          ],
          const Text('Canal',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _ChipChoice(
                  label: 'Todos',
                  selected: _source == null,
                  onTap: () => setState(() => _source = null)),
              _ChipChoice(
                  label: 'Mostrador',
                  selected: _source == 'POS',
                  onTap: () => setState(() => _source = 'POS')),
              _ChipChoice(
                  label: 'Mesa',
                  selected: _source == 'TABLE',
                  onTap: () => setState(() => _source = 'TABLE')),
              _ChipChoice(
                  label: 'Tienda online',
                  selected: _source == 'WEB',
                  onTap: () => setState(() => _source = 'WEB')),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Método de pago',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _ChipChoice(
                  label: 'Todos',
                  selected: _method == null,
                  onTap: () => setState(() => _method = null)),
              _ChipChoice(
                  label: 'Efectivo',
                  selected: _method == 'cash',
                  onTap: () => setState(() => _method = 'cash')),
              _ChipChoice(
                  label: 'Transferencia',
                  selected: _method == 'transfer',
                  onTap: () => setState(() => _method = 'transfer')),
              _ChipChoice(
                  label: 'Tarjeta',
                  selected: _method == 'card',
                  onTap: () => setState(() => _method = 'card')),
              _ChipChoice(
                  label: 'Fiado',
                  selected: _method == 'credit',
                  onTap: () => setState(() => _method = 'credit')),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_FilterSelection(
                  employee: _employee,
                  source: _source,
                  method: _method)),
              child: const Text('Aplicar filtros',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChipChoice(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 15,
              color: selected ? Colors.white : AppTheme.textPrimary,
              fontWeight: FontWeight.w600)),
      selected: selected,
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.surfaceGrey,
      onSelected: (_) => onTap(),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color:
                  selected ? AppTheme.primary : AppTheme.borderColor)),
    );
  }
}
