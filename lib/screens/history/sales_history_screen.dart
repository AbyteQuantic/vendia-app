import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/sync/sales_sync.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'receipt_detail_screen.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

enum _Range { today, yesterday, week, month, custom }

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  _Range _selected = _Range.today;
  DateTimeRange? _customRange;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _sales = const [];
  List<Map<String, dynamic>> _filtered = const [];

  late final ApiService _api;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _searchCtrl.addListener(_applyFilter);
    _pushThenLoad();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pushThenLoad() async {
    try { await SalesSyncService.pushToServer(); } catch (_) {}
    _load();
  }

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
        final start = today.subtract(Duration(days: today.weekday - 1));
        return (start: start, end: today);
      case _Range.month:
        return (start: DateTime(today.year, today.month, 1), end: today);
      case _Range.custom:
        if (_customRange == null) return null;
        return (start: _customRange!.start, end: _customRange!.end);
    }
  }

  String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() { _loading = true; _errorMessage = null; });
    try {
      final range = _resolveRange();
      final res = await _api.fetchSalesHistory(
        startDate: range == null ? null : _yyyymmdd(range.start),
        endDate: range == null ? null : _yyyymmdd(range.end),
        page: 1,
        perPage: 100,
      );
      final data = (res['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() { _sales = data; _loading = false; });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMessage = '$e'; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = _sales);
      return;
    }
    setState(() {
      _filtered = _sales.where((s) {
        final customer = _customerLabel(s).toLowerCase();
        final employee = ((s['employee_name'] as String?) ?? '').toLowerCase();
        final items = _itemsSummary(s).toLowerCase();
        final date = _formatDate(s['created_at'] as String?).toLowerCase();
        return customer.contains(q) ||
            employee.contains(q) ||
            items.contains(q) ||
            date.contains(q);
      }).toList();
    });
  }

  String _customerLabel(Map<String, dynamic> sale) {
    final name = (sale['customer_name_snapshot'] as String?) ?? '';
    if (name.isNotEmpty) return name;
    final method = (sale['payment_method'] as String?) ?? '';
    if (method == 'credit') return 'Fiado';
    return 'Venta Mostrador';
  }

  String _itemsSummary(Map<String, dynamic> sale) {
    final items = (sale['items'] as List?) ?? [];
    if (items.isEmpty) return '';
    final first = items.first;
    final name = (first is Map ? first['name'] : null) as String? ?? '';
    if (items.length == 1) return name;
    return '$name + ${items.length - 1} mas';
  }

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
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final ampm = d.hour >= 12 ? 'pm' : 'am';
    return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const months = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    return '${d.day} ${months[d.month - 1]}';
  }

  IconData _methodIcon(String method) => switch (method) {
    'card' || 'tarjeta' => Icons.credit_card_rounded,
    'transfer' || 'nequi' || 'daviplata' => Icons.phone_android_rounded,
    'credit' => Icons.menu_book_rounded,
    _ => Icons.payments_rounded,
  };

  Color _methodColor(String method) => switch (method) {
    'credit' => const Color(0xFFF59E0B),
    'card' || 'tarjeta' => const Color(0xFF3B82F6),
    'transfer' || 'nequi' || 'daviplata' => const Color(0xFF6D28D9),
    _ => AppTheme.success,
  };

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked == null) return;
    setState(() { _customRange = picked; _selected = _Range.custom; });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Historial de Ventas',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary)),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, producto o fecha...',
                hintStyle: TextStyle(fontSize: 15, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () { _searchCtrl.clear(); })
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          // Date chips
          _buildChips(),
          const SizedBox(height: 4),
          // Results count
          if (!_loading && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} venta${_filtered.length != 1 ? "s" : ""}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  if (_filtered.isNotEmpty)
                    Text(
                      'Total: ${_formatCOP(_filtered.fold<num>(0, (sum, s) => sum + ((s['total'] as num?) ?? 0)))}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: AppTheme.primary),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (label, range) in [
            ('Hoy', _Range.today),
            ('Ayer', _Range.yesterday),
            ('Semana', _Range.week),
            ('Mes', _Range.month),
          ])
            _chip(label, _selected == range, () {
              setState(() { _selected = range; _customRange = null; });
              _load();
            }),
          _chip(
            _customRange == null ? 'Fechas' : '${_yyyymmdd(_customRange!.start)} → ${_yyyymmdd(_customRange!.end)}',
            _selected == _Range.custom,
            _pickCustomRange,
            icon: Icons.calendar_today_rounded,
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary : Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14,
                    color: selected ? Colors.white : AppTheme.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Error: $_errorMessage', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Reintentar')),
        ],
      ));
    }
    if (_filtered.isEmpty) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded, size: 56, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('Sin ventas en este rango',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          SizedBox(height: 4),
          Text('Cambia el filtro o busca otra cosa.',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ));
    }
    return RefreshIndicator.adaptive(
      onRefresh: _pushThenLoad,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final sale = _filtered[i];
          final total = (sale['total'] as num?) ?? 0;
          final method = (sale['payment_method'] as String?) ?? 'cash';
          final customer = _customerLabel(sale);
          final items = _itemsSummary(sale);
          final employee = (sale['employee_name'] as String?) ?? '';
          final time = _formatTime(sale['created_at'] as String?);
          final date = _formatDate(sale['created_at'] as String?);
          final color = _methodColor(method);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReceiptDetailScreen(sale: sale),
                  ));
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      // Method icon
                      Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_methodIcon(method), color: color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (items.isNotEmpty)
                              Text(items,
                                  style: const TextStyle(
                                      fontSize: 13, color: AppTheme.textSecondary),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              '$employee  $date  $time',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade400),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Total + chevron
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatCOP(total),
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800,
                                  color: color)),
                          const SizedBox(height: 2),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: Colors.grey.shade300),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
