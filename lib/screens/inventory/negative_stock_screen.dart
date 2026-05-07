import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/collections/local_product.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Screen that lists every product whose reserved stock exceeds physical
/// stock, ordered from most-negative to least-negative.
///
/// The owner can regularize each product with one-tap +1/+5/+10 buttons or
/// open a dialog to enter a custom positive delta. Each adjustment:
///   1. Increments the local Isar stock via [DatabaseService.adjustStock]
///      so the badge and POS see the new number immediately.
///   2. PATCHes the product on the backend with the new absolute stock
///      value, which causes the Go handler to register a `manual_adjust`
///      kardex movement (see backend/internal/handlers/products.go).
///
/// As soon as a product's available stock returns to >= 0 the underlying
/// stream removes it from the list automatically.
class NegativeStockScreen extends StatefulWidget {
  /// Optional override for the products stream — set in widget tests.
  final Stream<List<LocalProduct>>? productsStream;

  /// Optional injected API service for tests that want to assert PATCH
  /// payloads without touching the network.
  final ApiService? apiService;

  const NegativeStockScreen({
    super.key,
    this.productsStream,
    this.apiService,
  });

  @override
  State<NegativeStockScreen> createState() => _NegativeStockScreenState();
}

class _NegativeStockScreenState extends State<NegativeStockScreen> {
  late final Stream<List<LocalProduct>> _stream;
  late final ApiService _api;
  final Set<String> _adjusting = <String>{};

  @override
  void initState() {
    super.initState();
    _stream = widget.productsStream ??
        DatabaseService.instance.watchNegativeStockProducts();
    _api = widget.apiService ?? ApiService(AuthService());
  }

  Future<void> _applyAdjustment(LocalProduct product, int delta) async {
    if (delta <= 0) return;
    final uuid = product.uuid;
    if (_adjusting.contains(uuid)) return;
    setState(() => _adjusting.add(uuid));
    HapticFeedback.lightImpact();
    try {
      // 1. Local stock first → reactive UI updates immediately.
      final newStock = await DatabaseService.instance.adjustStock(uuid, delta);
      if (newStock == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Producto no encontrado en local'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // 2. Server PATCH so backend kardex logs `manual_adjust`.
      try {
        await _api.updateProduct(uuid, {'stock': newStock});
      } catch (_) {
        // We don't undo the local bump — sync layer will retry the
        // server-side PATCH when connectivity returns. Surface a
        // gentle warning so the owner knows the kardex log is pending.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Stock local actualizado. Se sincronizará cuando vuelva la conexión.',
                style: TextStyle(fontSize: 14),
              ),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('negative_stock_adjust_snackbar'),
          content: Text(
            'Stock ajustado: +$delta unidades a ${product.name}',
            style: const TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _adjusting.remove(uuid));
    }
  }

  Future<void> _openManualAdjustDialog(LocalProduct product) async {
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.background,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Ajustar ${product.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock actual: ${product.stock}  ·  Reservado: ${product.reservedStock}',
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cuántas unidades agregar',
                  hintText: 'Ej: 8',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final raw = controller.text.trim();
                final parsed = int.tryParse(raw);
                if (parsed == null || parsed <= 0) {
                  Navigator.of(ctx).pop(null);
                  return;
                }
                Navigator.of(ctx).pop(parsed);
              },
              child: const Text('Aplicar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value != null && value > 0) {
      await _applyAdjustment(product, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text(
          'Regularizar stock negativo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<LocalProduct>>(
        stream: _stream,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AppTheme.success, size: 64),
                    SizedBox(height: 12),
                    Text(
                      'Todo en orden',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'No hay productos con stock negativo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            itemBuilder: (_, i) => _NegativeStockTile(
              product: items[i],
              busy: _adjusting.contains(items[i].uuid),
              onQuickAdjust: (delta) => _applyAdjustment(items[i], delta),
              onManualAdjust: () => _openManualAdjustDialog(items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _NegativeStockTile extends StatelessWidget {
  final LocalProduct product;
  final bool busy;
  final ValueChanged<int> onQuickAdjust;
  final VoidCallback onManualAdjust;

  const _NegativeStockTile({
    required this.product,
    required this.busy,
    required this.onQuickAdjust,
    required this.onManualAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final available = product.stock - product.reservedStock;
    final imgSrc = product.imageUrl;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 56,
                  height: 56,
                  color: Colors.white,
                  child: imgSrc != null && imgSrc.isNotEmpty
                      ? Image.network(
                          imgSrc,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.inventory_2_outlined,
                            color: AppTheme.textSecondary,
                          ),
                        )
                      : const Icon(
                          Icons.inventory_2_outlined,
                          color: AppTheme.textSecondary,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Stock: $available',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Físico ${product.stock} · Reservado ${product.reservedStock}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QuickButton(label: '+1', busy: busy, onTap: () => onQuickAdjust(1)),
              const SizedBox(width: 8),
              _QuickButton(label: '+5', busy: busy, onTap: () => onQuickAdjust(5)),
              const SizedBox(width: 8),
              _QuickButton(
                  label: '+10', busy: busy, onTap: () => onQuickAdjust(10)),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onManualAdjust,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Ajuste manual'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _QuickButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: busy ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.success,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
  }
}
