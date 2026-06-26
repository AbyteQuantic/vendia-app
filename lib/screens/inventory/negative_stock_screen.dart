import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/collections/local_product.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Lista los productos cuyo stock disponible quedó negativo (se vendieron sin
/// existencias registradas) y deja corregirlos indicando la cantidad REAL que
/// hay hoy, o sumando rápido. Cada ajuste:
///   1. Sube el stock local (Isar) → la UI y el POS lo ven al instante.
///   2. PATCH al backend con el stock absoluto → registra un `manual_adjust`
///      en el kardex.
/// Cuando el disponible vuelve a >= 0 el producto sale solo de la lista.
class NegativeStockScreen extends StatefulWidget {
  final Stream<List<LocalProduct>>? productsStream;
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

  Future<void> _applyDelta(LocalProduct product, int delta) async {
    if (delta <= 0) return;
    final uuid = product.uuid;
    if (_adjusting.contains(uuid)) return;
    setState(() => _adjusting.add(uuid));
    HapticFeedback.lightImpact();
    try {
      final newStock = await DatabaseService.instance.adjustStock(uuid, delta);
      if (newStock == null) {
        _snack('Producto no encontrado en local', ok: false);
        return;
      }
      try {
        await _api.updateProduct(uuid, {'stock': newStock});
      } catch (_) {
        _snack('Stock local actualizado. Se sincronizará cuando vuelva la conexión.',
            ok: false);
      }
      _snack('Stock de ${product.name} corregido a $newStock', ok: true,
          key: const Key('negative_stock_adjust_snackbar'));
    } finally {
      if (mounted) setState(() => _adjusting.remove(uuid));
    }
  }

  /// Corrige a una cantidad ABSOLUTA (la que el tendero dice tener hoy).
  Future<void> _correctTo(LocalProduct product, int target) async {
    final delta = target - product.stock;
    if (delta <= 0) {
      _snack('Ingrese una cantidad mayor al stock físico actual (${product.stock}).',
          ok: false);
      return;
    }
    await _applyDelta(product, delta);
  }

  void _snack(String m, {required bool ok, Key? key}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: key,
      content: Text(m, style: const TextStyle(fontSize: 15)),
      backgroundColor: ok ? AppTheme.success : AppTheme.warning,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openCorrectDialog(LocalProduct product) async {
    final controller = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Corregir ${product.name}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock físico actual: ${product.stock}',
                style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '¿Cuántas unidades tiene hoy?',
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
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop((parsed != null && parsed >= 0) ? parsed : null);
            },
            child: const Text('Corregir', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (target != null) await _correctTo(product, target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Regularizar stock', style: AppUI.title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: StreamBuilder<List<LocalProduct>>(
        stream: _stream,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) return _emptyState();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
            itemCount: items.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) return _intro(items.length);
              final p = items[i - 1];
              return _NegativeStockTile(
                product: p,
                busy: _adjusting.contains(p.uuid),
                onQuickAdjust: (d) => _applyDelta(p, d),
                onCorrect: () => _openCorrectDialog(p),
              );
            },
          );
        },
      ),
    );
  }

  Widget _intro(int count) => Padding(
        padding: const EdgeInsets.only(bottom: AppUI.s12),
        child: SoftCard(
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
            const SizedBox(width: AppUI.s12),
            Expanded(
              child: Text(
                '$count producto${count == 1 ? "" : "s"} se vendió sin stock '
                'registrado y quedó en negativo. Indique cuántas unidades tiene '
                'hoy de cada uno para corregirlo.',
                style: AppUI.bodySoft,
              ),
            ),
          ]),
        ),
      );

  Widget _emptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppUI.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 56),
            SizedBox(height: AppUI.s12),
            Text('Todo en orden',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppUI.ink)),
            SizedBox(height: 6),
            Text('No hay productos con stock negativo.',
                textAlign: TextAlign.center, style: AppUI.bodySoft),
          ]),
        ),
      );
}

class _NegativeStockTile extends StatelessWidget {
  final LocalProduct product;
  final bool busy;
  final ValueChanged<int> onQuickAdjust;
  final VoidCallback onCorrect;

  const _NegativeStockTile({
    required this.product,
    required this.busy,
    required this.onQuickAdjust,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final available = product.stock - product.reservedStock;
    final img = product.imageUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s12),
      child: SoftCard(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppUI.radiusSm),
              child: Container(
                width: 48,
                height: 48,
                color: Colors.white,
                child: img != null && img.isNotEmpty
                    ? Image.network(img, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.inventory_2_outlined, color: AppUI.inkSoft))
                    : const Icon(Icons.inventory_2_outlined, color: AppUI.inkSoft),
              ),
            ),
            const SizedBox(width: AppUI.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.bodyStrong.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('Disponible: $available',
                        style: const TextStyle(
                            color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Físico ${product.stock} · Reservado ${product.reservedStock}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppUI.bodySoft.copyWith(fontSize: 12)),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: AppUI.s12),
          // Acción principal: indicar la cantidad real.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: busy ? null : onCorrect,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Indicar cantidad real',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          const SizedBox(height: AppUI.s8),
          // Atajos para sumar rápido.
          Row(children: [
            Text('Sumar rápido:', style: AppUI.bodySoft.copyWith(fontSize: 12)),
            const SizedBox(width: 8),
            _QuickChip(label: '+1', busy: busy, onTap: () => onQuickAdjust(1)),
            const SizedBox(width: 6),
            _QuickChip(label: '+5', busy: busy, onTap: () => onQuickAdjust(5)),
            const SizedBox(width: 6),
            _QuickChip(label: '+10', busy: busy, onTap: () => onQuickAdjust(10)),
          ]),
        ]),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        side: const BorderSide(color: AppUI.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
