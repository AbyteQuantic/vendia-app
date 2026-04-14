import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_sale.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/margin_service.dart';
import '../../theme/app_theme.dart';
import 'sales_ideas_screen.dart';

class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  State<FinancialDashboardScreen> createState() =>
      _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  late final ApiService _api;
  final _db = DatabaseService.instance;
  String _period = 'today';
  bool _loading = true;

  // Financial data
  double _totalSales = 0;
  int _txCount = 0;
  double _cashInDrawer = 0;
  double _digitalMoney = 0;
  double _accountsReceivable = 0;
  double _profit = 0;
  double _dailyAvg = 0;

  // Local sales for today
  List<LocalSale> _localSales = [];

  // Employee performance
  List<_EmployeePerf> _employeePerf = [];

  // AI suggestions
  List<String> _suggestions = [];
  bool _suggestionsLoading = true;

  static const _periods = {'today': 'Hoy', 'week': 'Semana', 'month': 'Mes'};

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    if (_period == 'today') {
      await _loadLocalToday();
    } else {
      await _loadFromServer();
    }

    _loadSuggestions();
    if (mounted) setState(() => _loading = false);
  }

  /// "Hoy" uses Isar local data — same source as the Home dashboard
  Future<void> _loadLocalToday() async {
    final sales = await _db.getSalesToday();
    sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final margin = await MarginService.getMargin();

    double cash = 0, digital = 0, credit = 0;
    // Employee grouping
    final empMap = <String, _EmployeePerf>{};

    for (final s in sales) {
      switch (s.paymentMethod) {
        case 'cash':
          cash += s.total;
        case 'transfer' || 'card' || 'nequi' || 'daviplata':
          digital += s.total;
        case 'credit':
          credit += s.total;
        default:
          cash += s.total;
      }

      // Group by employee
      final empName = (s.employeeName != null && s.employeeName!.isNotEmpty)
          ? s.employeeName!
          : 'Sin asignar';
      empMap.putIfAbsent(empName, () => _EmployeePerf(name: empName));
      empMap[empName]!.totalSales += s.total;
      empMap[empName]!.txCount += 1;
    }

    final total = sales.fold<double>(0, (sum, s) => sum + s.total);

    // Profit = total - estimated cost using configured margin
    // If margin is 20%, cost = total / 1.20
    final estimatedCost = margin > 0 ? total / (1 + margin / 100) : total;
    final profit = total - estimatedCost;

    // Calculate per-employee profit proportionally
    for (final emp in empMap.values) {
      final empCost = margin > 0
          ? emp.totalSales / (1 + margin / 100)
          : emp.totalSales;
      emp.profit = emp.totalSales - empCost;
    }

    final perfList = empMap.values.toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

    if (mounted) {
      setState(() {
        _totalSales = total;
        _txCount = sales.length;
        _cashInDrawer = cash;
        _digitalMoney = digital;
        _accountsReceivable = credit;
        _profit = profit;
        _dailyAvg = total;
        _localSales = sales;
        _employeePerf = perfList;
      });
    }
  }

  /// Semana/Mes uses the backend aggregation endpoint
  Future<void> _loadFromServer() async {
    try {
      final data = await _api.fetchFinancialSummary(period: _period);
      if (mounted) {
        setState(() {
          _totalSales = (data['total_sales'] as num?)?.toDouble() ?? 0;
          _txCount = (data['transaction_count'] as num?)?.toInt() ?? 0;
          _cashInDrawer = (data['cash_in_drawer'] as num?)?.toDouble() ?? 0;
          _digitalMoney = (data['digital_money'] as num?)?.toDouble() ?? 0;
          _accountsReceivable =
              (data['accounts_receivable'] as num?)?.toDouble() ?? 0;
          _profit = (data['total_profit'] as num?)?.toDouble() ?? 0;
          _dailyAvg = (data['daily_average'] as num?)?.toDouble() ?? 0;
          _localSales = []; // No local data for historical periods
        });
      }
    } catch (_) {
      // If server fails for historical, show zeros
    }
  }

  void _loadSuggestions() {
    setState(() => _suggestionsLoading = true);

    // Smart local suggestions based on sales data
    final tips = <String>[];
    if (_txCount == 0) {
      tips.add('Registre su primera venta del dia para ver estadisticas.');
    } else {
      if (_cashInDrawer > _digitalMoney && _digitalMoney == 0) {
        tips.add(
            'Todas las ventas son en efectivo. Active Nequi o Daviplata para captar mas clientes.');
      }
      if (_txCount < 5) {
        tips.add(
            'Pocas ventas hoy. Considere una promocion "2x1" en productos de baja rotacion.');
      }
      if (_accountsReceivable > _totalSales * 0.3 &&
          _accountsReceivable > 0) {
        tips.add(
            'Las cuentas por cobrar son altas. Envie recordatorios por WhatsApp.');
      }
    }
    if (tips.isEmpty) {
      tips.add('Siga asi. Sus ventas van bien hoy.');
    }

    if (mounted) {
      setState(() {
        _suggestions = tips;
        _suggestionsLoading = false;
      });
    }
  }

  String _fmt(double amount) {
    final v = amount.round();
    if (v == 0) return '\$0';
    final s = v.abs().toString();
    final buffer = StringBuffer(v < 0 ? '-\$' : '\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return 'Hace ${diff.inDays}d';
  }

  String _methodLabel(String m) => switch (m) {
        'transfer' => 'Transferencia',
        'card' => 'Tarjeta',
        'credit' => 'Fiado',
        _ => 'Efectivo',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Finanzas',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // ── Period selector ─────────────────────────────────
                  Row(
                    children: _periods.entries.map((e) {
                      final sel = _period == e.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _period = e.key);
                            _load();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color:
                                  sel ? AppTheme.primary : AppTheme.surfaceGrey,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(e.value,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: sel
                                        ? Colors.white
                                        : AppTheme.textSecondary)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Total ventas (hero card) ───────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A2FA0), Color(0xFF2541B2)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.trending_up_rounded,
                                color: Colors.white70, size: 22),
                            const SizedBox(width: 8),
                            Text('Ventas ${_periods[_period]}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_fmt(_totalSales),
                              style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                        Text('$_txCount transacciones',
                            style: const TextStyle(
                                fontSize: 15, color: Colors.white54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Financial grid ─────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _FinCard(
                          icon: Icons.payments_rounded,
                          label: 'Efectivo en caja',
                          value: _fmt(_cashInDrawer),
                          bgColor: Colors.green.shade50,
                          fgColor: Colors.green.shade800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FinCard(
                          icon: Icons.phone_android_rounded,
                          label: 'Dinero digital',
                          value: _fmt(_digitalMoney),
                          bgColor: Colors.blue.shade50,
                          fgColor: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _FinCard(
                          icon: Icons.menu_book_rounded,
                          label: 'Cuentas x cobrar',
                          value: _fmt(_accountsReceivable),
                          bgColor: Colors.orange.shade50,
                          fgColor: Colors.orange.shade800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FinCard(
                          icon: Icons.show_chart_rounded,
                          label: 'Utilidad estimada',
                          value: _fmt(_profit),
                          bgColor: Colors.purple.shade50,
                          fgColor: Colors.purple.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── AI Suggestions (tap to navigate) ──────────────
                  GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SalesIdeasScreen(),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF7C3AED).withValues(alpha: 0.08),
                          const Color(0xFF3B82F6).withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            const Color(0xFF7C3AED).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Color(0xFF7C3AED), size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('Ideas para Vender Mas',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF7C3AED))),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: Color(0xFF7C3AED), size: 26),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_suggestionsLoading)
                          const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF7C3AED), strokeWidth: 2))
                        else
                          for (final tip in _suggestions) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('💡 ',
                                      style: TextStyle(fontSize: 16)),
                                  Expanded(
                                    child: Text(tip,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.black87,
                                            height: 1.4)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                  ),
                  const SizedBox(height: 24),

                  // ── Employee performance ───────────────────────────
                  if (_employeePerf.isNotEmpty) ...[
                    const Row(
                      children: [
                        Icon(Icons.people_rounded,
                            color: AppTheme.textPrimary, size: 22),
                        SizedBox(width: 8),
                        Text('Rendimiento del Equipo',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _employeePerf.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72, endIndent: 20),
                        itemBuilder: (_, i) {
                          final emp = _employeePerf[i];
                          final initial = emp.name.isNotEmpty
                              ? emp.name[0].toUpperCase()
                              : '?';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppTheme.primary
                                      .withValues(alpha: 0.12),
                                  child: Text(initial,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(emp.name,
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary)),
                                      Text(
                                          '${emp.txCount} venta${emp.txCount > 1 ? 's' : ''} registrada${emp.txCount > 1 ? 's' : ''}',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: AppTheme.textSecondary)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_fmt(emp.totalSales),
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primary)),
                                    Text('Ganancia: ${_fmt(emp.profit)}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade700)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Sales history ──────────────────────────────────
                  const Text('Historial de ventas',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),

                  if (_localSales.isEmpty && _period == 'today')
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Text('Sin ventas hoy todavia',
                            style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.textSecondary)),
                      ),
                    )
                  else if (_localSales.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < _localSales.length; i++) ...[
                            _buildLocalSaleTile(_localSales[i]),
                            if (i < _localSales.length - 1)
                              const Divider(
                                  height: 1, indent: 72, endIndent: 20),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildLocalSaleTile(LocalSale sale) {
    final items = sale.items;
    final label = items.isNotEmpty
        ? items.first.productName +
            (items.length > 1 ? ' + ${items.length - 1} mas' : '')
        : 'Venta';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              sale.paymentMethod == 'credit'
                  ? Icons.menu_book_rounded
                  : sale.paymentMethod == 'transfer'
                      ? Icons.phone_android_rounded
                      : Icons.payments_rounded,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                Text(
                  '${_methodLabel(sale.paymentMethod)}'
                  '${sale.employeeName != null && sale.employeeName!.isNotEmpty ? ' · ${sale.employeeName}' : ''}'
                  ' · ${_timeAgo(sale.createdAt)}',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(_fmt(sale.total),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success)),
        ],
      ),
    );
  }
}

class _FinCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color bgColor;
  final Color fgColor;

  const _FinCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fgColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fgColor, size: 24),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: fgColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: fgColor)),
          ),
        ],
      ),
    );
  }
}

class _EmployeePerf {
  final String name;
  double totalSales;
  double profit;
  int txCount;

  _EmployeePerf({
    required this.name,
    this.totalSales = 0,
    this.profit = 0,
    this.txCount = 0,
  });
}
