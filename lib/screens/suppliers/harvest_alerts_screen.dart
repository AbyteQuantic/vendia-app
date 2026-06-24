// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Anti-merma (Spec 075 F4): el proveedor ve sus perecederos por vencer +
/// cuántas tiendas hay cerca + un mensaje listo para difundir y liquidar.
class HarvestAlertsScreen extends StatefulWidget {
  final ApiService? api;
  const HarvestAlertsScreen({super.key, this.api});

  @override
  State<HarvestAlertsScreen> createState() => _HarvestAlertsScreenState();
}

class _HarvestAlertsScreenState extends State<HarvestAlertsScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.fetchHarvestAlerts(days: 7);
      if (!mounted) return;
      setState(() {
        _alerts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar las alertas.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Anti-merma', style: AppUI.title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _alerts.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppUI.s24),
                      child: Text('Nada por vencer pronto. 👌\nLe avisaremos cuando algo necesite salir rápido.',
                          textAlign: TextAlign.center, style: AppUI.bodySoft),
                    ))
                  : ListView.separated(
                      key: const Key('harvest_alerts_list'),
                      padding: const EdgeInsets.all(AppUI.s16),
                      itemCount: _alerts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
                      itemBuilder: (_, i) => _alertCard(_alerts[i]),
                    ),
    );
  }

  Widget _alertCard(Map<String, dynamic> a) {
    final days = (a['days_left'] as num?)?.toInt() ?? 0;
    final stores = (a['nearby_store_count'] as num?)?.toInt() ?? 0;
    final msg = (a['suggested_message'] ?? '').toString();
    final whenLabel = days <= 0 ? 'vence hoy' : (days == 1 ? 'vence mañana' : 'vence en $days días');

    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text((a['name'] ?? '').toString(), style: AppUI.bodyStrong)),
            MinimalBadge(label: whenLabel, color: AppTheme.warning),
          ]),
          const SizedBox(height: 4),
          Text('$stores tienda(s) cerca que podrían comprarlo', style: AppUI.bodySoft),
          const SizedBox(height: AppUI.s8),
          Container(
            padding: const EdgeInsets.all(AppUI.s8),
            decoration: BoxDecoration(
              color: AppUI.pageBg,
              borderRadius: BorderRadius.circular(AppUI.radiusSm),
              border: Border.all(color: AppUI.border),
            ),
            child: Text(msg, style: const TextStyle(fontSize: 13, color: AppUI.ink, height: 1.3)),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key('copy_${a['product_id']}'),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copiar mensaje para difundir'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: msg));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Mensaje copiado. Péguelo en su difusión por WhatsApp.'),
                    backgroundColor: AppTheme.success));
              },
            ),
          ),
        ],
      ),
    );
  }
}
