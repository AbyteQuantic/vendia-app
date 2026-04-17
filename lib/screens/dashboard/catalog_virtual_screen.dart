import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class CatalogVirtualScreen extends StatefulWidget {
  const CatalogVirtualScreen({super.key});

  @override
  State<CatalogVirtualScreen> createState() => _CatalogVirtualScreenState();
}

class _CatalogVirtualScreenState extends State<CatalogVirtualScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final ApiService _api;
  String? _slug;
  List<dynamic> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _api = ApiService(AuthService());
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await _api.fetchStoreConfig();
      final slug = config['store_slug'] as String? ?? '';

      final ordersRes = await _api.fetchOnlineOrders();

      if (mounted) {
        setState(() {
          _slug = slug;
          _orders = ordersRes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num amount) {
    final v = amount.round();
    if (v == 0) return '\$0';
    final s = v.abs().toString();
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  void _copyLink() {
    if (_slug == null || _slug!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configure el slug en Perfil del Negocio primero'),
        backgroundColor: AppTheme.warning, behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final url = 'https://vendia-admin.vercel.app/$_slug/menu';
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Link copiado: $url', style: const TextStyle(fontSize: 15)),
      backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating,
    ));
  }

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
        title: const Text('Catalogo Virtual',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Mi Tienda'),
            Tab(text: 'Pedidos'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(controller: _tabCtrl, children: [
              _buildStoreTab(),
              _buildOrdersTab(),
            ]),
    );
  }

  Widget _buildStoreTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Link card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1A2FA0), Color(0xFF2541B2)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Text('Tu tienda en linea', style: TextStyle(fontSize: 20,
                      fontWeight: FontWeight.bold, color: Colors.white)),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        _slug != null && _slug!.isNotEmpty
                            ? 'vendia-admin.vercel.app/$_slug/menu'
                            : 'Configure el slug primero',
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _copyLink,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Copiar', style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2FA0))),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Comparta este link en WhatsApp, Instagram o redes sociales para recibir pedidos.',
                  style: TextStyle(fontSize: 14, color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Stats
          Row(children: [
            Expanded(child: _statCard(
              Icons.shopping_bag_rounded, AppTheme.primary,
              '${_orders.length}', 'Pedidos totales')),
            const SizedBox(width: 12),
            Expanded(child: _statCard(
              Icons.hourglass_top_rounded, const Color(0xFFF59E0B),
              '${_orders.where((o) => (o as Map)['status'] == 'pending').length}',
              'Pendientes')),
          ]),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ]),
    );
  }

  Widget _buildOrdersTab() {
    final pending = _orders.where((o) => (o as Map)['status'] != 'completed').toList();
    if (pending.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_rounded, size: 56, color: AppTheme.textSecondary),
        SizedBox(height: 12),
        Text('Sin pedidos pendientes', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final o = pending[i] as Map<String, dynamic>;
          final status = o['status'] as String? ?? 'pending';
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: status == 'pending'
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                  : AppTheme.borderColor),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(o['customer_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == 'pending'
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                        : AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status == 'pending' ? 'Pendiente' : status,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: status == 'pending'
                              ? const Color(0xFFF59E0B) : AppTheme.success)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(_fmt((o['total_amount'] as num?) ?? 0),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
              const SizedBox(height: 8),
              Row(children: [
                if (status == 'pending')
                  Expanded(child: SizedBox(height: 44, child: ElevatedButton(
                    onPressed: () async {
                      await _api.updateOnlineOrderStatus(o['id'] as String, 'accepted');
                      _load();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Aceptar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ))),
                if (status == 'pending') const SizedBox(width: 8),
                if (status == 'accepted')
                  Expanded(child: SizedBox(height: 44, child: ElevatedButton(
                    onPressed: () async {
                      await _api.updateOnlineOrderStatus(o['id'] as String, 'completed');
                      _load();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Completar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ))),
              ]),
            ]),
          );
        },
      ),
    );
  }
}
