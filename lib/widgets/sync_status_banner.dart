import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../database/sync/sync_service.dart';
import '../theme/app_theme.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // Defensive lookup — the banner is purely informational, so rendering
    // nothing is the correct fallback when no SyncService provider is
    // attached (e.g. isolated widget tests that render a sub-tree
    // without the MultiProvider root).
    SyncService sync;
    try {
      sync = context.watch<SyncService>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }

    if (sync.status == SyncStatus.synced) {
      return const SizedBox.shrink();
    }

    final (Color bg, IconData icon, String text) = switch (sync.status) {
      SyncStatus.offline => (
          const Color(0xFFF59E0B),
          Icons.cloud_off_rounded,
          'Sin conexión — tus ventas están guardadas localmente',
        ),
      SyncStatus.syncing => (
          AppTheme.primary,
          Icons.sync_rounded,
          'Sincronizando...',
        ),
      SyncStatus.error => (
          AppTheme.error,
          Icons.warning_rounded,
          '${sync.pendingCount} operación${sync.pendingCount != 1 ? "es" : ""} pendiente${sync.pendingCount != 1 ? "s" : ""} de sincronizar',
        ),
      SyncStatus.synced => (
          AppTheme.success,
          Icons.cloud_done_rounded,
          'Sincronizado',
        ),
    };

    return Semantics(
      label: text,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: bg,
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (sync.status == SyncStatus.error)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    sync.syncNow();
                  },
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 60,
                      minHeight: 60,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Reintentar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
