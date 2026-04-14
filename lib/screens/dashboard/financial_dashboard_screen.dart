import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  State<FinancialDashboardScreen> createState() =>
      _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  late final ApiService _api;
  String _period = 'today';
  Map<String, dynamic> _summary = {};
  List<dynamic> _sales = [];
  bool _loading = true;

  static const _periodLabels = {
    'today': 'Hoy',
    'week': 'Semana',
    'month': 'Mes',
  };

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summaryRes = await _api.fetchFinancialSummary(period: _period);
      final historyRes = await _api.fetchSalesHistoryByPeriod(period: _period);
      if (mounted) {
        setState(() {
          _summary = summaryRes;
          _sales = historyRes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num? amount) {
    final v = (amount ?? 0).round();
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

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return 'Hace ${diff.inDays}d';
  }

  String _methodIcon(String? method) => switch (method) {
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
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // ── Period selector ─────────────────────────────────
                  Row(
                    children: _periodLabels.entries.map((e) {
                      final selected = _period == e.key;
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
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.surfaceGrey,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(e.value,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : AppTheme.textSecondary)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Summary cards ──────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.trending_up_rounded,
                          color: AppTheme.success,
                          label: 'Ventas',
                          value: _fmt(_summary['total_sales'] as num?),
                          subtitle: '${(_summary['transaction_count'] as num?)?.toInt() ?? 0} transacciones',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFF10B981),
                          label: 'Utilidad',
                          value: _fmt(_summary['total_profit'] as num?),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.payments_rounded,
                          color: const Color(0xFF3B82F6),
                          label: 'Efectivo en caja',
                          value: _fmt(_summary['cash_in_drawer'] as num?),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.phone_android_rounded,
                          color: const Color(0xFF8B5CF6),
                          label: 'Digital',
                          value: _fmt(_summary['digital_money'] as num?),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.menu_book_rounded,
                          color: const Color(0xFFF59E0B),
                          label: 'Cuentas x cobrar',
                          value: _fmt(_summary['accounts_receivable'] as num?),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.show_chart_rounded,
                          color: AppTheme.textSecondary,
                          label: 'Promedio diario',
                          value: _fmt(_summary['daily_average'] as num?),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── Sales history ──────────────────────────────────
                  Text('Historial de ventas',
                      style: const TextStyle(fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),

                  if (_sales.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Text('Sin ventas en este periodo',
                            style: TextStyle(fontSize: 18,
                                color: AppTheme.textSecondary)),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < _sales.length; i++) ...[
                            _buildSaleTile(_sales[i] as Map<String, dynamic>),
                            if (i < _sales.length - 1)
                              const Divider(height: 1, indent: 72, endIndent: 20),
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

  Widget _buildSaleTile(Map<String, dynamic> sale) {
    final items = sale['items'] as List? ?? [];
    final firstItem = items.isNotEmpty
        ? (items.first as Map<String, dynamic>)['name'] as String? ?? 'Venta'
        : 'Venta';
    final label = items.length > 1
        ? '$firstItem + ${items.length - 1} más'
        : firstItem;
    final method = sale['payment_method'] as String? ?? 'cash';
    final total = (sale['total'] as num?)?.toDouble() ?? 0;
    final employee = sale['employee_name'] as String? ?? '';
    final time = _timeAgo(sale['created_at'] as String?);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              method == 'credit'
                  ? Icons.menu_book_rounded
                  : method == 'transfer'
                      ? Icons.phone_android_rounded
                      : Icons.payments_rounded,
              color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                Text(
                  '${_methodIcon(method)}${employee.isNotEmpty ? ' · $employee' : ''} · $time',
                  style: const TextStyle(fontSize: 14,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(_fmt(total),
              style: const TextStyle(fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.success)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? subtitle;

  const _SummaryCard({
    required this.icon, required this.color,
    required this.label, required this.value, this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(fontSize: 14,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: const TextStyle(fontSize: 12,
                    color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}
