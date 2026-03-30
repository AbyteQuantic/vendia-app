import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import 'price_calculator_screen.dart';

/// Shows products from the invoice that still need a sale price.
class PricePendingScreen extends StatefulWidget {
  const PricePendingScreen({super.key});

  @override
  State<PricePendingScreen> createState() => _PricePendingScreenState();
}

class _PricePendingScreenState extends State<PricePendingScreen> {
  // Mock products awaiting pricing
  final List<_PendingProduct> _products = [
    const _PendingProduct(
        emoji: '\uD83E\uDD64', name: 'Coca-Cola 350ml', cost: 1500),
    const _PendingProduct(
        emoji: '\uD83E\uDDC3', name: 'Hit Naranja 1L', cost: 3200),
    const _PendingProduct(
        emoji: '\uD83D\uDCA7', name: 'Agua Cristal 600ml', cost: 1000),
  ];

  void _onPriceSet(int index, double newSalePrice) {
    setState(() {
      _products[index] = _products[index].copyWith(salePrice: newSalePrice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        _products.where((p) => p.salePrice == null).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Productos sin precio de venta',
        child: Column(
          children: [
            // Amber header
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 24,
                right: 24,
                bottom: 28,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    Semantics(
                      button: true,
                      label: 'Volver',
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 26),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '$pendingCount productos sin precio de venta',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'De la factura de Postobon',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Product list
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                itemCount: _products.length,
                itemBuilder: (context, index) {
                  final p = _products[index];
                  final hasSalePrice = p.salePrice != null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: hasSalePrice
                            ? const Color(0x3010B981)
                            : AppTheme.borderColor,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Emoji avatar
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0x20667EEA),
                                Color(0x20764BA2),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              p.emoji,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Comprado a: ${formatCOP(p.cost)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.error,
                                ),
                              ),
                              if (hasSalePrice) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Venta: ${formatCOP(p.salePrice!)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Button or check
                        if (hasSalePrice)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0x2010B981),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Color(0xFF10B981), size: 28),
                          )
                        else
                          SizedBox(
                            height: 48,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF667EEA),
                                    Color(0xFF764BA2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ElevatedButton(
                                onPressed: () async {
                                  HapticFeedback.lightImpact();
                                  final result =
                                      await Navigator.of(context).push<double>(
                                    MaterialPageRoute(
                                      builder: (_) => PriceCalculatorScreen(
                                        productName: p.name,
                                        productEmoji: p.emoji,
                                        costPrice: p.cost,
                                      ),
                                    ),
                                  );
                                  if (result != null) {
                                    _onPriceSet(index, result);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Poner Precio',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Done button when all priced
            if (pendingCount == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      // Guardar en backend + Isar local
                      try {
                        const uuid = Uuid();
                        final api = ApiService(AuthService());
                        final localProducts = <LocalProduct>[];

                        for (final p in _products.where((p) => p.salePrice != null)) {
                          final id = uuid.v4();
                          // Backend (PostgreSQL/Supabase)
                          await api.createProduct({
                            'id': id,
                            'name': p.name,
                            'price': p.salePrice,
                            'stock': 1,
                          });
                          // Local (Isar)
                          localProducts.add(LocalProduct()
                            ..uuid = id
                            ..name = p.name
                            ..price = p.salePrice!
                            ..stock = 1
                            ..isAvailable = true
                            ..requiresContainer = false
                            ..containerPrice = 0
                            ..clientUpdatedAt = DateTime.now());
                        }
                        await DatabaseService.instance
                            .upsertProducts(localProducts);
                      } catch (_) {}
                      if (!context.mounted) return;
                      // Pop back to root of inventory flow
                      Navigator.of(context)
                        ..pop()
                        ..pop()
                        ..pop();
                    },
                    icon: const Icon(Icons.check_circle_rounded,
                        size: 24, color: Colors.white),
                    label: const Text(
                      'Listo',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingProduct {
  final String emoji;
  final String name;
  final double cost;
  final double? salePrice;

  const _PendingProduct({
    required this.emoji,
    required this.name,
    required this.cost,
    this.salePrice,
  });

  _PendingProduct copyWith({double? salePrice}) {
    return _PendingProduct(
      emoji: emoji,
      name: name,
      cost: cost,
      salePrice: salePrice ?? this.salePrice,
    );
  }
}
