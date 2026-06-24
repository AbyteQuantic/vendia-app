import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/inventory_pdf.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'invoice_history_screen.dart';
import 'kardex_screen.dart';

class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  final _api = ApiService(AuthService());
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _branch;
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalProducts = 0;
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
        _products.length < _totalProducts) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchInventoryReport();
      if (!mounted) return;
      setState(() {
        _products = (data['products'] as List?)
                ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _totalProducts = (data['total_products'] as num?)?.toInt() ?? 0;
        _branch = data['branch'] as Map<String, dynamic>?;
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
      final data = await _api.fetchInventoryReport(page: _page);
      if (!mounted) return;
      final more = (data['products'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      setState(() {
        _products.addAll(more);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _exportPdf() async {
    HapticFeedback.mediumImpact();

    // If we haven't loaded all products yet, fetch them all for the PDF
    List<Map<String, dynamic>> allProducts = _products;
    if (_products.length < _totalProducts) {
      try {
        final data = await _api.fetchInventoryReport(page: 1, perPage: _totalProducts);
        allProducts = (data['products'] as List?)
                ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
                .toList() ??
            _products;
      } catch (_) {
        // Use what we have
      }
    }

    final branchName = _branch?['name'] as String? ?? 'Principal';

    try {
      final bytes = await buildInventoryReportPdfBytes(
        products: allProducts,
        branchName: branchName,
        totalProducts: _totalProducts,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Inventario_${branchName.replaceAll(' ', '_')}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al generar PDF: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de Inventario'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: 'Historial de facturas',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvoiceHistoryScreen()),
            ),
          ),
          if (!_loading && _products.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: 'Exportar PDF',
              onPressed: _exportPdf,
            ),
        ],
      ),
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
        _buildHeader(isDark),
        Expanded(
          child: _products.isEmpty
              ? const Center(
                  child: Text(
                    'Sin productos en inventario',
                    style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _products.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _products.length) {
                      return const Center(
                          child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ));
                    }
                    return _buildProductRow(_products[i], isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    final branchName = _branch?['name'] ?? 'Principal';
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
          Row(
            children: [
              const Icon(Icons.store, size: 20, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branchName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$_totalProducts productos',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> p, bool isDark) {
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final minStock = (p['min_stock'] as num?)?.toInt() ?? 0;
    final totalIn = (p['total_in'] as num?)?.toInt() ?? 0;
    final totalOut = (p['total_out'] as num?)?.toInt() ?? 0;
    final name = p['name'] as String? ?? '';
    final barcode = p['barcode'] as String? ?? '';
    final pres = p['presentation'] as String? ?? '';
    final content = p['content'] as String? ?? '';

    final isLow = minStock > 0 && stock <= minStock;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => KardexScreen(
              productId: p['id'] as String? ?? '',
              productName: name,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (barcode.isNotEmpty || pres.isNotEmpty)
                      Text(
                        [if (barcode.isNotEmpty) barcode, if (pres.isNotEmpty) '$pres $content']
                            .join(' · '),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _metricCol('Entr.', totalIn, AppTheme.success),
              const SizedBox(width: 12),
              _metricCol('Sal.', totalOut, AppTheme.error),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLow
                      ? AppTheme.error.withValues(alpha: 0.12)
                      : AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$stock',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: isLow ? AppTheme.error : AppTheme.success,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCol(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }
}
