import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// "El Cuaderno" — Real accounts receivable from backend. Zero mocks.
class CuadernoFiadosScreen extends StatefulWidget {
  const CuadernoFiadosScreen({super.key});

  @override
  State<CuadernoFiadosScreen> createState() => _CuadernoFiadosScreenState();
}

class _CuadernoFiadosScreenState extends State<CuadernoFiadosScreen> {
  late final ApiService _api;
  List<Map<String, dynamic>> _credits = [];
  bool _loading = true;
  String _filter = 'open';

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.fetchCredits(
          status: _filter == 'all' ? null : _filter, perPage: 100);
      final list = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() { _credits = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num amount) {
    final v = amount.round();
    if (v == 0) return '\$0';
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

  double get _totalPending => _credits.fold<double>(0,
      (s, c) => s + ((c['total_amount'] as num?) ?? 0) - ((c['paid_amount'] as num?) ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7), elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('El Cuaderno',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
      ),
      body: Column(children: [
        // Total header
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEA580C)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            const Icon(Icons.menu_book_rounded, color: Colors.white, size: 32),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total por cobrar', style: TextStyle(fontSize: 14, color: Colors.white70)),
              Text(_fmt(_totalPending), style: const TextStyle(fontSize: 28,
                  fontWeight: FontWeight.w800, color: Colors.white)),
            ])),
            Text('${_credits.length}', style: const TextStyle(fontSize: 24,
                fontWeight: FontWeight.w800, color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 12),

        // Filters
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            for (final f in [('open', 'Activos'), ('partial', 'Parcial'), ('paid', 'Pagados')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () { setState(() => _filter = f.$1); _load(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filter == f.$1 ? AppTheme.primary : AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(f.$2, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: _filter == f.$1 ? Colors.white : AppTheme.textSecondary)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _credits.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.menu_book_rounded, size: 56,
                          color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      const Text('Sin fiados', style: TextStyle(fontSize: 18,
                          color: AppTheme.textSecondary)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        itemCount: _credits.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _buildTile(_credits[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildTile(Map<String, dynamic> credit) {
    final customer = credit['customer'] as Map<String, dynamic>? ?? {};
    final name = customer['name'] as String? ?? 'Sin nombre';
    final phone = customer['phone'] as String? ?? '';
    final total = (credit['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (credit['paid_amount'] as num?)?.toInt() ?? 0;
    final balance = total - paid;
    final status = credit['status'] as String? ?? 'open';

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FiadoDetailScreen(creditId: credit['id'] as String),
        ));
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: Color(0xFFF59E0B))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w600, color: Colors.black87)),
            Text(status == 'paid' ? 'Pagado' : 'Debe ${_fmt(balance)}',
                style: TextStyle(fontSize: 15,
                    color: status == 'paid' ? AppTheme.success : const Color(0xFFEA580C))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmt(total), style: const TextStyle(fontSize: 17,
                fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            if (phone.isNotEmpty)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  launchUrl(Uri.parse('https://wa.me/57$phone'),
                      mode: LaunchMode.externalApplication);
                },
                child: const Padding(padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 22)),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FIADO DETAIL with timeline + abono button
// ═══════════════════════════════════════════════════════════════════════════════

class _FiadoDetailScreen extends StatefulWidget {
  final String creditId;
  const _FiadoDetailScreen({required this.creditId});

  @override
  State<_FiadoDetailScreen> createState() => _FiadoDetailScreenState();
}

class _FiadoDetailScreenState extends State<_FiadoDetailScreen> {
  late final ApiService _api;
  Map<String, dynamic>? _credit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchCreditDetail(widget.creditId);
      if (mounted) setState(() { _credit = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num amount) {
    final v = amount.round();
    if (v == 0) return '\$0';
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

  void _showAbonoModal() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2))),
            const Text('Registrar Abono', style: TextStyle(fontSize: 22,
                fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl, autofocus: true,
              keyboardType: TextInputType.number, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '\$ ', prefixStyle: TextStyle(fontSize: 36,
                    fontWeight: FontWeight.bold, color: Colors.grey.shade400),
                hintText: '0', hintStyle: TextStyle(fontSize: 36, color: Colors.grey.shade300),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 60,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final amount = int.tryParse(ctrl.text) ?? 0;
                  if (amount <= 0) return;
                  Navigator.of(ctx).pop();
                  try {
                    await _api.registerAbono(widget.creditId, amount: amount);
                    HapticFeedback.mediumImpact();
                    _load();
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'), backgroundColor: AppTheme.error,
                    ));
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 24),
                label: const Text('Registrar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _credit == null) {
      return Scaffold(backgroundColor: const Color(0xFFFFFBF7),
          appBar: AppBar(backgroundColor: const Color(0xFFFFFBF7), elevation: 0),
          body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)));
    }

    final c = _credit!;
    final customer = c['customer'] as Map<String, dynamic>? ?? {};
    final name = customer['name'] as String? ?? '';
    final total = (c['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (c['paid_amount'] as num?)?.toInt() ?? 0;
    final balance = total - paid;
    final status = c['status'] as String? ?? 'open';
    final payments = (c['payments'] as List?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7), elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded,
            color: AppTheme.textPrimary, size: 28),
            onPressed: () => Navigator.of(context).pop()),
        title: Text(name, style: const TextStyle(fontSize: 22,
            fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // Balance
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: status == 'paid' ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: status == 'paid' ? Colors.green.shade200 : Colors.orange.shade200),
          ),
          child: Column(children: [
            Text(status == 'paid' ? 'Cuenta saldada' : 'Saldo pendiente',
                style: TextStyle(fontSize: 16, color: status == 'paid'
                    ? Colors.green.shade700 : Colors.orange.shade700)),
            const SizedBox(height: 4),
            Text(_fmt(balance > 0 ? balance : 0),
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800,
                    color: status == 'paid' ? Colors.green.shade700 : Colors.orange.shade800)),
            if (total > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (paid / total).clamp(0, 1).toDouble(), minHeight: 8,
                  backgroundColor: Colors.black.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.success))),
              const SizedBox(height: 6),
              Text('Fiado: ${_fmt(total)} · Abonado: ${_fmt(paid)}',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Movimientos', style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 12),

        // Debt entry
        _entry(Icons.shopping_cart_rounded, const Color(0xFFEA580C),
            'Compra fiada', '+${_fmt(total)}', c['created_at'] as String? ?? ''),

        // Payments
        for (final p in payments)
          _entry(Icons.payments_rounded, AppTheme.success, 'Abono',
              '-${_fmt((p as Map<String, dynamic>)['amount'] as num? ?? 0)}',
              p['created_at'] as String? ?? ''),

        const SizedBox(height: 80),
      ]),
      bottomNavigationBar: status != 'paid' ? Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(color: const Color(0xFFFFFBF7),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12, offset: const Offset(0, -2))]),
        child: SizedBox(height: 60, child: ElevatedButton.icon(
          onPressed: _showAbonoModal,
          icon: const Icon(Icons.payments_rounded, size: 24),
          label: const Text('Registrar Abono', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        )),
      ) : null,
    );
  }

  Widget _entry(IconData icon, Color color, String title, String amount, String date) {
    String fmt = '';
    if (date.isNotEmpty) {
      final dt = DateTime.tryParse(date);
      if (dt != null) {
        final d = DateTime.now().difference(dt);
        if (d.inMinutes < 60) fmt = 'Hace ${d.inMinutes} min';
        else if (d.inHours < 24) fmt = 'Hace ${d.inHours}h';
        else fmt = 'Hace ${d.inDays}d';
      }
    }
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4, offset: const Offset(0, 2))]),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
              if (fmt.isNotEmpty) Text(fmt, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ])),
            Text(amount, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ]))),
      ],
    ));
  }
}
