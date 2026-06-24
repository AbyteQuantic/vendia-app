// Spec: specs/053 sync offline de mesas — vista de cuentas abiertas.
//
// Migrado del sistema local-only (TablesController + SharedPreferences, grilla
// de 10 mesas mock) al sistema REAL sincronizado: lee las mesas abiertas desde
// Isar (`watchAllOpenTabs`, respaldado por OrderTickets del backend) y las trae
// del servidor con `listOpenTabs` (GET /tables/open) al entrar y al refrescar,
// para que las cuentas abiertas en CUALQUIER dispositivo sean visibles aquí.
// Abrir/agregar consumo pasa por la caja (POS), que ya empuja al tab real
// (commitOrderToTab→upsertTableTab); cobrar pasa por TabReviewScreen (closeOrder).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../database/collections/local_table_tab.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/sync_status_banner.dart';
import '../pos/pos_screen.dart';
import 'tab_review_screen.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  @override
  void initState() {
    super.initState();
    _pull();
  }

  /// Trae las mesas abiertas del servidor a Isar (lado PULL del sync). Si no
  /// hay red, la lista local sigue mostrándose — falla en silencio.
  Future<void> _pull() async {
    try {
      final tabs = await ApiService(AuthService()).listOpenTabs();
      await DatabaseService.instance.applyServerOpenTabs(tabs);
    } catch (_) {
      // offline-safe
    }
  }

  void _openReview(LocalTableTab tab) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TabReviewScreen(
          sessionToken: tab.sessionToken ?? '',
          tableLabel: tab.label,
          orderId: tab.orderId,
        ),
      ),
    );
  }

  Future<void> _openPos() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PosScreen()),
    );
    if (mounted) _pull(); // al volver de la caja, refrescar la lista
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
        title: const Text(
          'Mesas',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPos,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Abrir / agregar en caja',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: Semantics(
        label: 'Pantalla de mesas',
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _pull,
                child: StreamBuilder<List<LocalTableTab>>(
                  stream: DatabaseService.instance.watchAllOpenTabs(),
                  builder: (context, snapshot) {
                    final tabs = snapshot.data ?? const <LocalTableTab>[];
                    if (tabs.isEmpty) return const _EmptyTabs();
                    // Orden estable por label para que no salten al refrescar.
                    final sorted = [...tabs]
                      ..sort((a, b) => a.label.compareTo(b.label));
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _OpenTabCard(
                        tab: sorted[i],
                        onTap: () => _openReview(sorted[i]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío — scrollable para que el RefreshIndicator (deslizar para
/// refrescar) funcione aunque no haya mesas.
class _EmptyTabs extends StatelessWidget {
  const _EmptyTabs();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        const Icon(Icons.table_restaurant_rounded,
            size: 64, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        const Text(
          'No hay cuentas abiertas',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Abra una cuenta agregando productos en la caja. Aparecerá aquí y '
            'en cualquier otro dispositivo de la tienda.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _OpenTabCard extends StatelessWidget {
  final LocalTableTab tab;
  final VoidCallback onTap;

  const _OpenTabCard({required this.tab, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final units = tab.items.fold<int>(0, (s, i) => s + i.quantity);
    final saldo = tab.pendingBalance > 0 ? tab.pendingBalance : tab.grossTotal;
    return Semantics(
      button: true,
      label: 'Cuenta de ${tab.label}, saldo ${formatCOP(saldo)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.table_restaurant_rounded,
                    color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$units producto${units == 1 ? "" : "s"}'
                      '${tab.synced ? "" : " · sin sincronizar"}',
                      style: const TextStyle(
                          fontSize: 15, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCOP(saldo),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ver y cobrar',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
