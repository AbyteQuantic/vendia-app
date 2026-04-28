import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../online_store/promo_management_screen.dart';

/// Inteligencia de productos — what to act on.
///
/// One screen, three lists, all backed by GET /analytics/products-insights:
///   1. Más vendidos (Top sellers)  — push these, they print money.
///   2. Casi no se venden (Slow movers) — promote, discount or retire.
///   3. Próximos a vencer (Expiring) — discount NOW or lose the cost.
///      Each row gets a direct "Crear promoción" button so the dueño
///      can act on a expiring item without hunting in the menu.
///
/// Reachable from the main dashboard's "Más vendido" card (now
/// tappable). Replaces the previous dead-end where the card just
/// showed a name with no follow-through.
class ProductInsightsScreen extends StatefulWidget {
  const ProductInsightsScreen({super.key});

  @override
  State<ProductInsightsScreen> createState() => _ProductInsightsScreenState();
}

class _ProductInsightsScreenState extends State<ProductInsightsScreen> {
  late final ApiService _api;
  bool _loading = true;
  String? _errorMsg;
  Map<String, dynamic>? _data;
  String _period = '30d';

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final data = await _api.fetchProductInsights(period: _period);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'No se pudieron cargar los productos: $e';
        _loading = false;
      });
    }
  }

  void _setPeriod(String p) {
    if (_period == p) return;
    HapticFeedback.lightImpact();
    setState(() => _period = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Inteligencia de productos',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            labelStyle:
                TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            tabs: [
              Tab(icon: Icon(Icons.trending_up_rounded), text: 'Más vendidos'),
              Tab(icon: Icon(Icons.trending_down_rounded), text: 'Casi no salen'),
              Tab(icon: Icon(Icons.event_busy_rounded), text: 'Por vencer'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMsg != null
                ? _ErrorState(message: _errorMsg!, onRetry: _load)
                : Column(
                    children: [
                      _PeriodChips(period: _period, onChanged: _setPeriod),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _TopSellersTab(
                                items: _list('top_sellers'),
                                onRefresh: _load),
                            _SlowMoversTab(
                                items: _list('slow_movers'),
                                onRefresh: _load),
                            _ExpiringTab(
                                items: _list('expiring_soon'),
                                onRefresh: _load),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  List<Map<String, dynamic>> _list(String key) {
    final raw = (_data?[key] as List?) ?? const [];
    return raw.cast<Map<String, dynamic>>();
  }
}

class _PeriodChips extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;
  const _PeriodChips({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = const [('7d', '7 días'), ('30d', '30 días'), ('90d', '90 días')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        children: options.map((o) {
          final active = o.$1 == period;
          return ChoiceChip(
            label: Text(o.$2,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppTheme.textPrimary)),
            selected: active,
            selectedColor: AppTheme.primary,
            backgroundColor: AppTheme.surfaceGrey,
            onSelected: (_) => onChanged(o.$1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color:
                        active ? AppTheme.primary : AppTheme.borderColor)),
          );
        }).toList(),
      ),
    );
  }
}

// ── Tabs ──────────────────────────────────────────────────────────

class _TopSellersTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  const _TopSellersTab({required this.items, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(
        icon: Icons.shopping_bag_outlined,
        message:
            'Aún no tenemos suficientes ventas para identificar productos estrella.\nRegistre algunas ventas y vuelva en unos días.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _TopSellerTile(rank: i + 1, item: items[i]),
      ),
    );
  }
}

class _TopSellerTile extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> item;
  const _TopSellerTile({required this.rank, required this.item});

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '') as String;
    final qty = (item['quantity'] as num?)?.toInt() ?? 0;
    final revenue = (item['revenue'] as num?)?.toDouble() ?? 0;
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    final imageUrl = (item['image_url'] ?? '') as String;
    final medal = rank == 1
        ? '🥇'
        : rank == 2
            ? '🥈'
            : rank == 3
                ? '🥉'
                : '#$rank';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        SizedBox(
          width: 32,
          child: Text(medal,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        _ProductThumbnail(imageUrl: imageUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('$qty unidades · ${_money(revenue)}',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 2),
              Text('Quedan $stock en inventario',
                  style: TextStyle(
                      fontSize: 13,
                      color: stock <= 5
                          ? AppTheme.error
                          : AppTheme.textSecondary,
                      fontWeight: stock <= 5
                          ? FontWeight.w700
                          : FontWeight.w400)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SlowMoversTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  const _SlowMoversTab({required this.items, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(
        icon: Icons.thumb_up_alt_rounded,
        message:
            '¡Buenas noticias! Todos sus productos están rotando bien en este período.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ActionBanner(
            color: AppTheme.warning,
            icon: Icons.lightbulb_outline_rounded,
            text:
                'Estos productos casi no salen. Considere bajar el precio, '
                'destacarlos en una promoción o moverlos a la vista del cliente.',
            buttonLabel: 'Ir a promociones',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PromoManagementScreen())),
          ),
          const SizedBox(height: 12),
          ...items.map((it) => _SlowMoverTile(item: it)),
        ],
      ),
    );
  }
}

class _SlowMoverTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _SlowMoverTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '') as String;
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final qty = (item['quantity_sold'] as num?)?.toInt() ?? 0;
    final imageUrl = (item['image_url'] ?? '') as String;
    final lastSale = item['last_sale_at'] as String?;
    final lastSaleStr = _lastSaleLabel(lastSale);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        _ProductThumbnail(imageUrl: imageUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                qty == 0
                    ? 'Sin ventas en el período · $stock en stock · ${_money(price)}'
                    : 'Solo $qty unidades vendidas · $stock en stock',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 2),
              Text('Última venta: $lastSaleStr',
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.warning)),
            ],
          ),
        ),
      ]),
    );
  }

  String _lastSaleLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'nunca';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return 'nunca';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 30) return 'hace ${diff.inDays} días';
    if (diff.inDays >= 1) return 'hace ${diff.inDays} días';
    if (diff.inHours >= 1) return 'hace ${diff.inHours} h';
    return 'hace minutos';
  }
}

class _ExpiringTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  const _ExpiringTab({required this.items, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyHint(
        icon: Icons.check_circle_outline_rounded,
        message:
            'No hay productos por vencer en los próximos 30 días. ¡Inventario sano!',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ActionBanner(
            color: AppTheme.error,
            icon: Icons.priority_high_rounded,
            text:
                'Estos productos vencen pronto. Bájeles el precio o haga una promoción '
                'antes de que pierdan valor.',
            buttonLabel: 'Crear promoción ahora',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PromoManagementScreen())),
          ),
          const SizedBox(height: 12),
          ...items.map((it) => _ExpiringTile(item: it)),
        ],
      ),
    );
  }
}

class _ExpiringTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ExpiringTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '') as String;
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final cost = (item['purchase_price'] as num?)?.toDouble() ?? 0;
    final daysLeft = (item['days_left'] as num?)?.toInt() ?? 0;
    final imageUrl = (item['image_url'] ?? '') as String;
    final urgent = daysLeft <= 7;
    final loss = cost > 0 ? cost * stock : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: urgent
            ? AppTheme.error.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: urgent
                ? AppTheme.error.withValues(alpha: 0.4)
                : AppTheme.borderColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _ProductThumbnail(imageUrl: imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: urgent
                          ? AppTheme.error
                          : AppTheme.warning,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      daysLeft <= 0
                          ? 'YA VENCIÓ'
                          : daysLeft == 1
                              ? 'Vence mañana'
                              : 'Vence en $daysLeft días',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      '$stock en stock · ${_money(price)}'
                      '${loss > 0 ? '  · perdería ${_money(loss.toDouble())}' : ''}',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PromoManagementScreen())),
              icon: const Icon(Icons.local_offer_rounded, size: 18),
              label: const Text('Crear promoción para este',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    urgent ? AppTheme.error : AppTheme.warning,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Building blocks ───────────────────────────────────────────────

class _ProductThumbnail extends StatelessWidget {
  final String imageUrl;
  const _ProductThumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        height: 56,
        color: AppTheme.surfaceGrey,
        child: imageUrl.isEmpty
            ? const Icon(Icons.image_not_supported_outlined,
                color: AppTheme.textSecondary, size: 22)
            : Image.network(imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_not_supported_outlined,
                    color: AppTheme.textSecondary,
                    size: 22)),
      ),
    );
  }
}

class _ActionBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final String buttonLabel;
  final VoidCallback onPressed;
  const _ActionBanner({
    required this.color,
    required this.icon,
    required this.text,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary))),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(buttonLabel,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyHint({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off_rounded,
            size: 56, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

String _money(double v) {
  if (v == 0) return r'$0';
  final cents = v.round();
  final s = cents.abs().toString();
  final buf = StringBuffer(cents < 0 ? r'-$' : r'$');
  final start = s.length % 3;
  if (start > 0) buf.write(s.substring(0, start));
  for (int i = start; i < s.length; i += 3) {
    if (i > 0) buf.write('.');
    buf.write(s.substring(i, i + 3));
  }
  return buf.toString();
}
