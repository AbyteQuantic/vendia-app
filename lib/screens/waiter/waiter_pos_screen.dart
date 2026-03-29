import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';

/// WaiterPosScreen — Mesero agrega productos al pedido de una mesa.
/// Amber color scheme, sends order to cashier via "Enviar a Caja".
class WaiterPosScreen extends StatefulWidget {
  final String tableLabel;
  final String waiterName;

  const WaiterPosScreen({
    super.key,
    this.tableLabel = 'Mesa 4',
    this.waiterName = 'Carlos',
  });

  @override
  State<WaiterPosScreen> createState() => _WaiterPosScreenState();
}

class _WaiterPosScreenState extends State<WaiterPosScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── Amber palette ──
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);

  // ── Mock products ──
  final List<_MockProduct> _allProducts = const [
    _MockProduct(name: 'Cerveza \u00c1guila', emoji: '\ud83c\udf7a', price: 3500),
    _MockProduct(name: 'Empanada', emoji: '\ud83e\udd5f', price: 2000),
    _MockProduct(name: 'Hamburguesa', emoji: '\ud83c\udf54', price: 12000),
    _MockProduct(name: 'Perro Caliente', emoji: '\ud83c\udf2d', price: 5000),
    _MockProduct(name: 'Gaseosa', emoji: '\ud83e\udd64', price: 2500),
    _MockProduct(name: 'Agua', emoji: '\ud83d\udca7', price: 1500),
    _MockProduct(name: 'Bandeja Paisa', emoji: '\ud83c\udf5b', price: 18000),
    _MockProduct(name: 'Arepa', emoji: '\ud83e\uddc0', price: 3000),
    _MockProduct(name: 'Jugo Natural', emoji: '\ud83e\uddc3', price: 4000),
    _MockProduct(name: 'Caf\u00e9', emoji: '\u2615', price: 2000),
  ];

  // Quantity map: product name -> qty
  final Map<String, int> _quantities = {};

  List<_MockProduct> get _filtered {
    if (_searchQuery.isEmpty) return _allProducts;
    final q = _searchQuery.toLowerCase();
    return _allProducts.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  int get _totalCount =>
      _quantities.values.fold(0, (sum, qty) => sum + qty);

  double get _totalPrice {
    double total = 0;
    for (final entry in _quantities.entries) {
      final product = _allProducts.firstWhere((p) => p.name == entry.key);
      total += product.price * entry.value;
    }
    return total;
  }

  void _addProduct(_MockProduct product) {
    HapticFeedback.lightImpact();
    setState(() {
      _quantities[product.name] = (_quantities[product.name] ?? 0) + 1;
    });
  }

  void _sendToCashier() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pedido ${widget.tableLabel} enviado a caja',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Row(
          children: [
            Text(
              widget.tableLabel,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _amber,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.waiterName,
                style: const TextStyle(
                  fontSize: 16, // badge text (exempt: fits in compact badge)
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Search bar with camera icon ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 18),
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: _amber, size: 24),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.camera_alt_rounded,
                      color: _amber, size: 24),
                  tooltip: 'Escanear',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    // TODO: camera scan
                  },
                ),
              ),
            ),
          ),

          // ── Product grid (2 columns) ──
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Sin resultados',
                      style: TextStyle(
                          fontSize: 18, color: AppTheme.textSecondary),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final product = _filtered[i];
                      final qty = _quantities[product.name] ?? 0;
                      return _WaiterProductCard(
                        product: product,
                        quantity: qty,
                        onTap: () => _addProduct(product),
                      );
                    },
                  ),
          ),

          // ── Bottom bar: amber gradient ──
          if (_totalCount > 0)
            Container(
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_amber, _amberDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Left: table + count + total
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.tableLabel} \u00b7 $_totalCount productos',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          formatCOP(_totalPrice),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right: "Enviar a Caja" button
                  Semantics(
                    button: true,
                    label: 'Enviar pedido a caja',
                    child: GestureDetector(
                      onTap: _sendToCashier,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              '\ud83d\udd14',
                              style: TextStyle(fontSize: 22),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Enviar a Caja',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Product card for waiter POS ────────────────────────────────────────────────

class _WaiterProductCard extends StatelessWidget {
  final _MockProduct product;
  final int quantity;
  final VoidCallback onTap;

  const _WaiterProductCard({
    required this.product,
    required this.quantity,
    required this.onTap,
  });

  static const Color _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar ${product.name}, ${formatCOP(product.price)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: quantity > 0 ? _amber : AppTheme.borderColor,
              width: quantity > 0 ? 2.5 : 1.5,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji with gradient background
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _amber.withValues(alpha: 0.15),
                          _amber.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      product.emoji,
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatCOP(product.price),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _amber,
                    ),
                  ),
                ],
              ),

              // Quantity badge
              if (quantity > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: _amber,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$quantity',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mock product model (waiter context) ────────────────────────────────────────

class _MockProduct {
  final String name;
  final String emoji;
  final double price;

  const _MockProduct({
    required this.name,
    required this.emoji,
    required this.price,
  });
}
