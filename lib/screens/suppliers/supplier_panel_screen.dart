// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'supplier_inbox_screen.dart';
import 'harvest_alerts_screen.dart';

/// Panel del proveedor (Spec 075): atajo a pedidos entrantes + anti-merma.
/// Visible solo si el tenant tiene EnableSupplierMode (modo "Vendo a tiendas").
class SupplierPanelScreen extends StatelessWidget {
  const SupplierPanelScreen({super.key});

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
        title: const Text('Panel de proveedor', style: AppUI.title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppUI.s16),
          children: [
            _card(context,
                key: 'panel_inbox',
                icon: Icons.inbox_rounded,
                title: 'Pedidos entrantes',
                subtitle: 'Lo que las tiendas le piden.',
                screen: const SupplierInboxScreen()),
            const SizedBox(height: AppUI.s12),
            _card(context,
                key: 'panel_alerts',
                icon: Icons.eco_rounded,
                title: 'Anti-merma',
                subtitle: 'Perecederos por vencer + tiendas cerca para liquidar.',
                screen: const HarvestAlertsScreen()),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context,
      {required String key,
      required IconData icon,
      required String title,
      required String subtitle,
      required Widget screen}) {
    return InkWell(
      key: Key(key),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
      child: Container(
        padding: const EdgeInsets.all(AppUI.s16),
        decoration: AppUI.card(r: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppUI.radiusSm),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: AppUI.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppUI.bodyStrong),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppUI.bodySoft),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
          ],
        ),
      ),
    );
  }
}
