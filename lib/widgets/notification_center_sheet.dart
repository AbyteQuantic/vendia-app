import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_notification.dart';
import '../screens/online_orders/online_orders_screen.dart';
import '../screens/pos/cuaderno_fiados_screen.dart';
import '../theme/app_theme.dart';

/// Bottom-sheet "Activity Feed" that replaces the legacy flat list.
///
/// Responsibilities:
///   - Render a scrollable DraggableScrollableSheet with a drag
///     handle + title.
///   - Group items into `Hoy` / `Ayer` / `Más antiguas` sticky
///     subheaders.
///   - For each item, render a tile with a colored avatar (icon
///     coded by [NotificationKind]), bold title + body, right-side
///     relative time, and an unread blue dot when `isRead == false`.
///   - On tap, deep-link to the KDS (web orders) or the Cuaderno
///     (fiado). System notifications are non-interactive.
///
/// The sheet does NOT own the data. The caller passes the already
/// parsed list; this keeps the widget trivially testable and lets
/// the POS screen continue polling the backend at its own cadence.
Future<void> showNotificationCenter(
  BuildContext context, {
  required List<AppNotification> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotificationCenterSheet(items: items),
  );
}

class _NotificationCenterSheet extends StatelessWidget {
  const _NotificationCenterSheet({required this.items});

  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_rounded,
                      color: AppTheme.primary, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Actividad reciente',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const _EmptyState()
                  : _FeedList(items: items, scrollCtrl: scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 60,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 10),
          const Text(
            'Sin actividad nueva',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            'Aquí verás pedidos web, fiados y alertas.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({required this.items, required this.scrollCtrl});

  final List<AppNotification> items;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    // Group by date bucket, preserving the already descending order
    // of the input list. The caller is responsible for sorting.
    final now = DateTime.now();
    final buckets = <NotificationDateBucket, List<AppNotification>>{};
    for (final n in items) {
      final b = bucketFor(n.createdAt, now: now);
      buckets.putIfAbsent(b, () => <AppNotification>[]).add(n);
    }

    // Fixed visual order regardless of map insertion order.
    const order = [
      NotificationDateBucket.today,
      NotificationDateBucket.yesterday,
      NotificationDateBucket.older,
    ];

    // Flatten to a single ListView with headers inline. Sticky
    // headers would be nicer but they require an extra dep; the
    // inline variant is accessible and plays well with the
    // draggable sheet.
    final rows = <_FeedRow>[];
    for (final bucket in order) {
      final list = buckets[bucket];
      if (list == null || list.isEmpty) continue;
      rows.add(_FeedRow.header(bucketLabel(bucket)));
      for (final n in list) {
        rows.add(_FeedRow.item(n));
      }
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final row = rows[i];
        if (row.isHeader) {
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 4 : 16, bottom: 8, left: 6),
            child: Text(
              row.header!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppTheme.textSecondary.withValues(alpha: 0.75),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _NotificationTile(notification: row.item!, now: now),
        );
      },
    );
  }
}

/// Discriminated union so the ListView.builder can render headers
/// and items from a single flat array without fighting indices.
class _FeedRow {
  _FeedRow.header(this.header)
      : item = null,
        isHeader = true;
  _FeedRow.item(this.item)
      : header = null,
        isHeader = false;

  final bool isHeader;
  final String? header;
  final AppNotification? item;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.now});

  final AppNotification notification;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final visual = NotificationVisual.of(notification.kind);
    final ago = relativeTime(notification.createdAt, now: now);
    final interactive = notification.kind != NotificationKind.system;

    return Material(
      color: notification.isRead ? Colors.white : const Color(0xFFF5F8FF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: interactive ? () => _handleTap(context) : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: notification.isRead
                  ? const Color(0xFFEDE8E0)
                  : visual.color.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Semantic avatar — colored square with the kind icon.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visual.icon, color: visual.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        height: 1.25,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Right column: "hace 2 min" + unread dot, top-aligned
              // so they line up with the title cap height.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (ago.isNotEmpty)
                    Text(
                      ago,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (!notification.isRead)
                    Container(
                      key: const Key('notification_unread_dot'),
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    HapticFeedback.selectionClick();
    // The sheet is a route — closing it first keeps the navigation
    // stack shallow (otherwise the KDS would sit on top of the
    // bottom sheet and back-nav would feel laggy).
    Navigator.of(context).pop();
    switch (notification.kind) {
      case NotificationKind.webOrder:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OnlineOrdersScreen()),
        );
        break;
      case NotificationKind.fiado:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CuadernoFiadosScreen()),
        );
        break;
      case NotificationKind.system:
        break; // non-interactive by contract
    }
  }
}
