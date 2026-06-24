import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Smart reorder screen: groups low-stock products by supplier so the
/// tendero can place one order per supplier via WhatsApp, call, or SMS.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key});

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  final _api = ApiService(AuthService());
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchReorderSuggestions();
      if (!mounted) return;
      setState(() {
        _groups = data;
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

  String _buildOrderMessage(Map<String, dynamic> group) {
    final supplierName = group['supplier_name'] as String? ?? '';
    final products = (group['products'] as List?) ?? [];
    final buffer = StringBuffer();
    buffer.writeln('Hola${supplierName.isNotEmpty ? ' $supplierName' : ''}, necesito pedir:');
    buffer.writeln();
    for (final p in products) {
      final name = p['name'] as String? ?? '';
      final qty = (p['suggest_order'] as num?)?.toInt() ?? 1;
      buffer.writeln('• $name — $qty unidades');
    }
    buffer.writeln();
    buffer.writeln('¿Me confirman disponibilidad? Gracias.');
    return buffer.toString();
  }

  void _contactSheet(Map<String, dynamic> group) {
    final phone = (group['supplier_phone'] as String? ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    final name = group['supplier_name'] as String? ?? 'Proveedor';
    final message = _buildOrderMessage(group);
    final encodedMsg = Uri.encodeComponent(message);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Pedir a $name',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(message,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                ),
              ),
              const SizedBox(height: 12),
              if (phone.isNotEmpty) ...[
                _actionTile(
                  icon: Icons.chat_rounded,
                  label: 'Enviar por WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () {
                    Navigator.pop(ctx);
                    _launch('https://wa.me/$phone?text=$encodedMsg');
                  },
                ),
                _actionTile(
                  icon: Icons.phone_rounded,
                  label: 'Llamar',
                  color: AppTheme.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _launch('tel:$phone');
                  },
                ),
                _actionTile(
                  icon: Icons.sms_rounded,
                  label: 'Enviar SMS',
                  color: AppTheme.warning,
                  onTap: () {
                    Navigator.pop(ctx);
                    _launch('sms:$phone?body=$encodedMsg');
                  },
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sin teléfono — asigna un proveedor a estos productos',
                    style: TextStyle(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              // Copy message
              _actionTile(
                icon: Icons.copy_rounded,
                label: 'Copiar mensaje',
                color: AppTheme.textSecondary,
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mensaje copiado')),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Text('Pedidos sugeridos',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
              : _groups.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success),
                          SizedBox(height: 12),
                          Text('Todo bien',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('No hay productos con stock bajo',
                              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _groups.length,
                        itemBuilder: (_, i) => _buildGroup(_groups[i]),
                      ),
                    ),
    );
  }

  Widget _buildGroup(Map<String, dynamic> group) {
    final name = group['supplier_name'] as String? ?? 'Sin proveedor';
    final emoji = group['supplier_emoji'] as String? ?? '';
    final phone = group['supplier_phone'] as String? ?? '';
    final products = (group['products'] as List?) ?? [];
    final totalItems = (group['total_items'] as num?)?.toInt() ?? 0;
    final hasPhone = phone.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Supplier header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            decoration: BoxDecoration(
              color: hasPhone
                  ? AppTheme.primary.withValues(alpha: 0.06)
                  : AppTheme.warning.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                if (emoji.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                      Text('$totalItems unidades por pedir · ${products.length} productos',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                if (hasPhone)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      _contactSheet(group);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_checkout_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Pedir',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Product list
          ...products.map<Widget>((p) {
            final pName = p['name'] as String? ?? '';
            final stock = (p['stock'] as num?)?.toInt() ?? 0;
            final minStock = (p['min_stock'] as num?)?.toInt() ?? 0;
            final suggest = (p['suggest_order'] as num?)?.toInt() ?? 1;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    stock == 0 ? Icons.error_rounded : Icons.warning_amber_rounded,
                    size: 18,
                    color: stock == 0 ? AppTheme.error : AppTheme.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(pName,
                        style: const TextStyle(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('$stock/$minStock',
                      style: TextStyle(
                        fontSize: 13,
                        color: stock == 0 ? AppTheme.error : AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('+$suggest',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.success)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
