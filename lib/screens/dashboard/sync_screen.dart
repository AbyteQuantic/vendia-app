import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../database/database_service.dart';
import '../../database/sync/sync_service.dart';
import '../../theme/app_theme.dart';

/// Sync & Connection diagnostic screen — Gerontodiseño.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  int _localProducts = 0;
  int _localSales = 0;
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _loadLocalCounts();
  }

  Future<void> _loadLocalCounts() async {
    final db = DatabaseService.instance;
    final products = await db.getAllProducts();
    final sales = await db.getSalesToday();
    if (mounted) {
      setState(() {
        _localProducts = products.length;
        _localSales = sales.length;
        _loadingCounts = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Conexión y Sincronización',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: Consumer<SyncService>(
        builder: (context, sync, _) {
          final isOnline = sync.status != SyncStatus.offline;
          final isSyncing = sync.status == SyncStatus.syncing;
          final isSynced = sync.status == SyncStatus.synced;
          final pending = sync.pendingCount;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // ── Connection Status ─────────────────────────────────
                _StatusCard(
                  icon: isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: isOnline ? AppTheme.success : AppTheme.error,
                  title: isOnline ? 'En línea' : 'Sin conexión',
                  subtitle: isSynced
                      ? 'Todos los datos están sincronizados'
                      : isSyncing
                          ? 'Sincronizando datos...'
                          : '$pending operaciones pendientes',
                ),

                const SizedBox(height: 16),

                // ── Pending Operations ────────────────────────────────
                _StatusCard(
                  icon: Icons.cloud_upload_rounded,
                  color: pending > 0
                      ? const Color(0xFFF59E0B)
                      : AppTheme.success,
                  title: pending > 0
                      ? '$pending operaciones pendientes'
                      : 'Todo sincronizado',
                  subtitle: pending > 0
                      ? 'Se enviarán cuando haya conexión'
                      : 'No hay datos pendientes de subir',
                ),

                const SizedBox(height: 24),

                // ── Local Data Counts ─────────────────────────────────
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Datos Locales',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                ),
                const SizedBox(height: 12),

                if (_loadingCounts)
                  const Center(child: CircularProgressIndicator(
                      color: AppTheme.primary))
                else
                  Row(
                    children: [
                      Expanded(
                        child: _DataCard(
                          icon: Icons.inventory_2_rounded,
                          label: 'Productos',
                          count: _localProducts,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DataCard(
                          icon: Icons.receipt_long_rounded,
                          label: 'Ventas hoy',
                          count: _localSales,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 32),

                // ── Sync Button ───────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: isSyncing
                        ? null
                        : () async {
                            HapticFeedback.mediumImpact();
                            await sync.syncNow();
                            await _loadLocalCounts();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Sincronización completada',
                                      style: TextStyle(fontSize: 16)),
                                  backgroundColor: AppTheme.success,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                          },
                    icon: isSyncing
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.sync_rounded, size: 26),
                    label: Text(
                      isSyncing ? 'Sincronizando...' : 'Forzar Sincronización',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  'La sincronización automática ocurre cada 30 segundos cuando hay conexión.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _StatusCard({
    required this.icon, required this.color,
    required this.title, required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _DataCard({
    required this.icon, required this.label,
    required this.count, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text('$count', style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(
              fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
