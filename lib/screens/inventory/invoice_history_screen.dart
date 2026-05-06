import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class InvoiceHistoryScreen extends StatefulWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  final _api = ApiService(AuthService());
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _api.fetchInvoiceLogs();
      if (!mounted) return;
      final list = (resp['data'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      setState(() {
        _logs = list;
        _total = (resp['total'] as num?)?.toInt() ?? list.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Facturas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: AppTheme.textSecondary),
                      SizedBox(height: 12),
                      Text('Sin facturas registradas',
                          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => _buildTile(_logs[i]),
                  ),
                ),
    );
  }

  Widget _buildTile(Map<String, dynamic> log) {
    final provider = log['provider_name'] as String? ?? 'Desconocido';
    final count = (log['product_count'] as num?)?.toInt() ?? 0;
    final created = (log['created_count'] as num?)?.toInt() ?? 0;
    final updated = (log['updated_count'] as num?)?.toInt() ?? 0;
    final total = (log['invoice_total'] as num?)?.toDouble() ?? 0;
    final userName = log['user_name'] as String? ?? '';
    final summary = log['summary'] as String? ?? '';
    final createdAt = log['created_at'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.receipt_long_rounded, color: AppTheme.success, size: 22),
        ),
        title: Text(provider,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(
          [
            '$count productos ($created nuevos, $updated restock)',
            if (userName.isNotEmpty) userName,
            _formatDate(createdAt),
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: total > 0
            ? Text(
                '\$${_fmtNum(total.round())}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary),
              )
            : null,
        children: [
          if (summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(summary,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }
}
