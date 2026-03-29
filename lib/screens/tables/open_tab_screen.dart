import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import '../pos/cart_controller.dart';
import '../pos/checkout_screen.dart';
import '../pos/sale_success_screen.dart';
import 'tables_controller.dart';
import 'widgets/tab_item_row.dart';

class OpenTabScreen extends StatefulWidget {
  final int tableNumber;
  final TablesController ctrl;

  const OpenTabScreen({
    super.key,
    required this.tableNumber,
    required this.ctrl,
  });

  @override
  State<OpenTabScreen> createState() => _OpenTabScreenState();
}

class _OpenTabScreenState extends State<OpenTabScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    final products = CartController.mockProducts;
    if (_search.isEmpty) return products;
    final q = _search.toLowerCase();
    return products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  void _addItem(Product product) {
    HapticFeedback.lightImpact();
    widget.ctrl.addItemToTable(widget.tableNumber, product);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} agregado',
            style: const TextStyle(fontSize: 18)),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _closeTab() async {
    final tab = widget.ctrl.getTable(widget.tableNumber);
    if (tab.items.isEmpty) {
      widget.ctrl.closeTable(widget.tableNumber);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final result = await Navigator.of(context).push<CheckoutResult>(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          items: tab.items,
          formattedTotal: widget.ctrl.formattedTotal(widget.tableNumber),
          total: tab.total,
        ),
      ),
    );

    if (result != null && result.confirmed) {
      widget.ctrl.closeTable(widget.tableNumber);
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleSuccessScreen(
            total: formatCOP(tab.total),
            paymentMethod: result.paymentMethod,
          ),
        ),
      );

      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver a mesas',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          'Mesa ${widget.tableNumber}',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Cuenta abierta de mesa ${widget.tableNumber}',
        child: ListenableBuilder(
          listenable: widget.ctrl,
          builder: (context, _) {
            final tab = widget.ctrl.getTable(widget.tableNumber);

            return Column(
              children: [
                // Search bar for adding products
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 18),
                    onChanged: (q) => setState(() => _search = q),
                    decoration: InputDecoration(
                      hintText: 'Agregar producto...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppTheme.primary, size: 24),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // Product list for adding
                if (_search.isNotEmpty)
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: _filteredProducts
                          .map((p) => _QuickAddChip(
                              product: p, onTap: () => _addItem(p)))
                          .toList(),
                    ),
                  ),

                // Current tab items
                Expanded(
                  child: tab.items.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_rounded,
                                  size: 64, color: AppTheme.textSecondary),
                              SizedBox(height: 12),
                              Text(
                                'Cuenta vacía',
                                style: TextStyle(
                                    fontSize: 20,
                                    color: AppTheme.textSecondary),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Busque productos arriba para agregar',
                                style: TextStyle(
                                    fontSize: 18,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          children: tab.items
                              .map((item) => TabItemRow(
                                    item: item,
                                    onIncrement: () => widget.ctrl
                                        .incrementItem(
                                            widget.tableNumber, item.product),
                                    onDecrement: () => widget.ctrl
                                        .decrementItem(
                                            widget.tableNumber, item.product),
                                  ))
                              .toList(),
                        ),
                ),

                // Total + Close tab button
                if (tab.items.isNotEmpty)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                        24, 16, 24, 16 + MediaQuery.of(context).padding.bottom),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGrey,
                      border: const Border(
                          top: BorderSide(color: AppTheme.borderColor)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary)),
                            Text(
                              widget.ctrl.formattedTotal(widget.tableNumber),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton.icon(
                            onPressed: _closeTab,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.success,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            icon: const Icon(Icons.receipt_rounded,
                                size: 24, color: Colors.white),
                            label: const Text('CERRAR CUENTA Y COBRAR',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _QuickAddChip({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: Semantics(
        button: true,
        label: 'Agregar ${product.name}',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.formattedPrice,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
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
