import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sync_status_banner.dart';
import 'tables_controller.dart';
import 'open_tab_screen.dart';
import 'widgets/table_card.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late final TablesController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TablesController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openTable(int tableNumber) {
    HapticFeedback.lightImpact();
    _ctrl.openTable(tableNumber);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OpenTabScreen(
          tableNumber: tableNumber,
          ctrl: _ctrl,
        ),
      ),
    );
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
      ),
      body: Semantics(
        label: 'Pantalla de mesas',
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (context, _) {
                  final openCount = _ctrl.tables.where((t) => t.isOpen).length;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$openCount mesa${openCount != 1 ? "s" : ""} ocupada${openCount != 1 ? "s" : ""}',
                              style: const TextStyle(
                                  fontSize: 18, color: AppTheme.textSecondary),
                            ),
                            Text(
                              '${_ctrl.tableCount} mesas',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: _ctrl.tables.length,
                          itemBuilder: (_, i) {
                            final tab = _ctrl.tables[i];
                            return TableCard(
                              tab: tab,
                              onTap: () => _openTable(tab.tableNumber),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
