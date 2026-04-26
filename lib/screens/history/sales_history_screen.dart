import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'receipt_detail_screen.dart';

/// Sales history — unified ledger (POS + WEB + TABLE).
///
/// Filters: Hoy / Ayer / Esta semana / Este mes / Personalizado.
/// The "Personalizado" chip opens a date-range picker; the others
/// resolve client-side to a [start, end] pair so the backend only
/// has to honour the start_date/end_date contract.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

enum _Range { today, yesterday, week, month, custom }

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  _Range _selected = _Range.today;
  DateTimeRange? _customRange;
  String _query = '';
  String? _source; // null = all
  String? _paymentMethod;
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _sales = const [];

  late final ApiService _api;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  /// Resolve the active filter to a (start, end) pair. Inclusive on
  /// both ends — the backend accepts end-of-day implicitly via its
  /// `end_date + 1d` strict-less-than handling, so we just send the
  /// dates as YYYY-MM-DD.
  ({DateTime start, DateTime end})? _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_selected) {
      case _Range.today:
        return (start: today, end: today);
      case _Range.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return (start: y, end: y);
      case _Range.week:
        // Week starts on Monday in es-CO. weekday is 1..7 Mon..Sun.
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start: start, end: today);
      case _Range.month:
        return (
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
      case _Range.custom:
        if (_customRange == null) return null;
        return (
          start: _customRange!.start,
          end: _customRange!.end,
        );
    }
  }

  String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final range = _resolveRange();
      final res = await _api.fetchSalesHistory(
        startDate: range == null ? null : _yyyymmdd(range.start),
        endDate: range == null ? null : _yyyymmdd(range.end),
        source: _source,
        paymentMethod: _paymentMethod,
        query: _query.trim().isEmpty ? null : _query.trim(),
        page: 1,
        perPage: 50,
      );
      final data = (res['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _sales = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'No pudimos cargar el historial: $e';
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          ),
      helpText: 'Elige el rango',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _selected = _Range.custom;
    });
    _load();
  }

  IconData _methodIcon(String method) => switch (method) {
        'card' => Icons.credit_card_rounded,
        'transfer' => Icons.swap_horiz_rounded,
        'credit' => Icons.menu_book_rounded,
        _ => Icons.payments_rounded,
      };

  String _formatCOP(num value) {
    final v = value.round();
    final s = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-\$' : '\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Historial de Ventas',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.textPrimary),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildChips(),
          _buildSourceChips(),
          const SizedBox(height: 8),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _RangeChip(
            label: 'Hoy',
            selected: _selected == _Range.today,
            onTap: () => setState(() {
              _selected = _Range.today;
              _customRange = null;
              _load();
            }),
          ),
          _RangeChip(
            label: 'Ayer',
            selected: _selected == _Range.yesterday,
            onTap: () => setState(() {
              _selected = _Range.yesterday;
              _customRange = null;
              _load();
            }),
          ),
          _RangeChip(
            label: 'Esta semana',
            selected: _selected == _Range.week,
            onTap: () => setState(() {
              _selected = _Range.week;
              _customRange = null;
              _load();
            }),
          ),
          _RangeChip(
            label: 'Este mes',
            selected: _selected == _Range.month,
            onTap: () => setState(() {
              _selected = _Range.month;
              _customRange = null;
              _load();
            }),
          ),
          _RangeChip(
            label: _customRange == null
                ? 'Personalizado'
                : '${_yyyymmdd(_customRange!.start)} → ${_yyyymmdd(_customRange!.end)}',
            selected: _selected == _Range.custom,
            icon: Icons.calendar_today_rounded,
            onTap: _pickCustomRange,
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SourceChip(
            label: 'Todos',
            active: _source == null,
            onTap: () => setState(() {
              _source = null;
              _load();
            }),
          ),
          _SourceChip(
            label: 'Mostrador',
            active: _source == 'POS',
            onTap: () => setState(() {
              _source = 'POS';
              _load();
            }),
          ),
          _SourceChip(
            label: 'Mesa',
            active: _source == 'TABLE',
            onTap: () => setState(() {
              _source = 'TABLE';
              _load();
            }),
          ),
          _SourceChip(
            label: 'Web',
            active: _source == 'WEB',
            onTap: () => setState(() {
              _source = 'WEB';
              _load();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sales.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded,
                  size: 64, color: AppTheme.textSecondary),
              SizedBox(height: 16),
              Text(
                'Sin ventas en este rango',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              SizedBox(height: 4),
              Text(
                'Cambia el filtro para ver otros días.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _sales.length,
        itemBuilder: (_, i) {
          final sale = _sales[i];
          final total = (sale['total'] as num?) ?? 0;
          final method = (sale['payment_method'] as String?) ?? 'cash';
          final source = (sale['source'] as String?) ?? 'POS';
          final receiptNumber = (sale['receipt_number'] as num?)?.toInt() ?? 0;
          return _SaleCard(
            time: _formatTime(sale['created_at'] as String?),
            total: _formatCOP(total),
            method: method,
            receipt: receiptNumber > 0 ? '#$receiptNumber' : '—',
            source: source,
            methodIcon: _methodIcon(method),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReceiptDetailScreen(sale: sale),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary
                : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : Colors.grey.shade200,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected ? Colors.white : AppTheme.textSecondary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.4)
                  : Colors.grey.shade200,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.time,
    required this.total,
    required this.method,
    required this.receipt,
    required this.source,
    required this.methodIcon,
    required this.onTap,
  });

  final String time;
  final String total;
  final String method;
  final String receipt;
  final String source;
  final IconData methodIcon;
  final VoidCallback onTap;

  static const _sourceLabels = {
    'POS': 'Mostrador',
    'TABLE': 'Mesa',
    'WEB': 'Web',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(methodIcon, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            receipt,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _sourceLabels[source] ?? source,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  total,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
