import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class KardexScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const KardexScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<KardexScreen> createState() => _KardexScreenState();
}

class _KardexScreenState extends State<KardexScreen> {
  final _api = ApiService(AuthService());
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _movements = [];
  Map<String, dynamic>? _product;
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _total = 0;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _movements.length < _total) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchProductKardex(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = data['product'] as Map<String, dynamic>?;
        _movements = (data['movements'] as List?)
                ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      _page++;
      final data = await _api.fetchProductKardex(widget.productId, page: _page);
      if (!mounted) return;
      final more = (data['movements'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      setState(() {
        _movements.addAll(more);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('Kardex — ${widget.productName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
              : _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    return Column(
      children: [
        if (_product != null) _buildProductHeader(isDark),
        Expanded(
          child: _movements.isEmpty
              ? const Center(
                  child: Text(
                    'Sin movimientos registrados',
                    style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _movements.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _movements.length) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ));
                    }
                    return _buildMovementTile(_movements[i], isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductHeader(bool isDark) {
    final p = _product!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surfaceGrey,
        border: Border(bottom: BorderSide(color: AppTheme.borderColor.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p['name'] ?? '',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _chip('Stock: ${p['stock'] ?? 0}', AppTheme.primary),
              if ((p['barcode'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 8),
                _chip(p['barcode'], AppTheme.textSecondary),
              ],
              if ((p['presentation'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 8),
                _chip('${p['presentation']} ${p['content'] ?? ''}', AppTheme.textSecondary),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$_total movimientos registrados',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildMovementTile(Map<String, dynamic> mov, bool isDark) {
    final type = mov['movement_type'] as String? ?? '';
    final qty = (mov['quantity'] as num?)?.toInt() ?? 0;
    final before = (mov['stock_before'] as num?)?.toInt() ?? 0;
    final after = (mov['stock_after'] as num?)?.toInt() ?? 0;
    final createdAt = mov['created_at'] as String? ?? '';
    final userName = mov['user_name'] as String? ?? '';
    final notes = mov['notes'] as String? ?? '';

    final info = _movementInfo(type);
    final isPositive = qty > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: info.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(info.icon, color: info.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(createdAt),
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (userName.isNotEmpty)
                    Text(userName, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  if (notes.isNotEmpty)
                    Text(notes, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isPositive ? "+" : ""}$qty',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isPositive ? AppTheme.success : AppTheme.error,
                  ),
                ),
                Text(
                  '$before → $after',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
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

  _MovementInfo _movementInfo(String type) {
    return switch (type) {
      'sale' => const _MovementInfo('Venta', Icons.shopping_cart, AppTheme.error),
      'invoice_scan' => const _MovementInfo('Factura IA', Icons.document_scanner, AppTheme.success),
      'voice_ingest' => const _MovementInfo('Voz IA', Icons.mic, AppTheme.success),
      'order_cancel' => const _MovementInfo('Pedido cancelado', Icons.cancel_outlined, AppTheme.warning),
      'sale_cancel' => const _MovementInfo('Venta cancelada', Icons.undo, AppTheme.warning),
      'table_tab' => const _MovementInfo('Cuenta mesa', Icons.table_restaurant, AppTheme.error),
      'tab_close' => const _MovementInfo('Cierre cuenta', Icons.receipt_long, AppTheme.error),
      'manual_adjust' => const _MovementInfo('Ajuste manual', Icons.edit, AppTheme.primary),
      'initial_stock' => const _MovementInfo('Stock inicial', Icons.inventory_2, AppTheme.success),
      _ => _MovementInfo(type, Icons.help_outline, AppTheme.textSecondary),
    };
  }
}

class _MovementInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _MovementInfo(this.label, this.icon, this.color);
}
