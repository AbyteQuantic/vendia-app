import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Semantic category for a notification.
///
/// The backend persists a free-form `type` string on each row
/// (`online_order`, `fiado_accepted`, `fiado_cancelled`, `info`, …).
/// The activity feed only cares about three buckets, each bound to
/// its own color + icon language so the cashier can scan the list
/// at a glance without reading the text.
enum NotificationKind {
  /// Web orders flowing in from the public catalog. Routed to the
  /// KDS detail on tap.
  webOrder,

  /// Fiado lifecycle events: handshake accepted, canceled, paid,
  /// debt added. Routed to the Cuaderno on tap.
  fiado,

  /// Everything else: inventory alerts, generic system messages,
  /// `info` and unknown `type` values. Non-routable by default.
  system,
}

/// A single item rendered by [NotificationCenterSheet].
///
/// Intentionally kept as a value object so the categorization logic
/// is pure and unit-testable ([fromApi]). The backend contract is
/// `{id, type, title, body, is_read, created_at}`.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    required this.rawType,
    this.orderId,
    this.fiadoId,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final bool isRead;

  /// Parsed server timestamp or `null` when the payload was
  /// malformed. A null value degrades gracefully: the tile shows
  /// no "hace N min" affordance and the item falls to the bottom
  /// of the feed.
  final DateTime? createdAt;

  /// The original `type` string — kept for debugging / future
  /// back-compat branches without changing the enum surface.
  final String rawType;

  /// Optional deep-link identifiers extracted from the server
  /// payload. The backend stores them on a nested `data` map
  /// (see `online_orders.go::CreateNotification`) but older rows
  /// may not have them — `null` is a valid state.
  final String? orderId;
  final String? fiadoId;

  /// Bucketize a backend `type` string into a UI kind. Exposed as
  /// a pure function so widget tests can assert the mapping table
  /// without spinning up a MaterialApp.
  static NotificationKind kindFromType(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.startsWith('online_order') || t == 'order' || t == 'web_order') {
      return NotificationKind.webOrder;
    }
    if (t.startsWith('fiado') || t == 'debt' || t == 'payment') {
      return NotificationKind.fiado;
    }
    return NotificationKind.system;
  }

  /// Parse a raw API row. Returns `null` if the payload lacks the
  /// minimum fields (id + title) — defensive for forward-compat
  /// with new backend event types that the app hasn't shipped yet.
  static AppNotification? fromApi(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    final title = raw['title']?.toString() ?? '';
    if (id.isEmpty && title.isEmpty) return null;

    // `data` is an optional nested bag the backend uses for deep
    // links (order_id / fiado_id). Treat it as opaque: if the
    // shape isn't a Map we silently drop it rather than crashing.
    String? orderId;
    String? fiadoId;
    final data = raw['data'];
    if (data is Map) {
      orderId = data['order_id']?.toString() ?? data['order_uuid']?.toString();
      fiadoId = data['fiado_id']?.toString() ?? data['fiado_token']?.toString();
    }

    return AppNotification(
      id: id,
      kind: kindFromType(raw['type']?.toString()),
      title: title,
      body: raw['body']?.toString() ?? '',
      isRead: raw['is_read'] == true,
      createdAt: _parseDate(raw['created_at']),
      rawType: raw['type']?.toString() ?? '',
      orderId: orderId,
      fiadoId: fiadoId,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

/// Visual tokens derived from [NotificationKind]. Kept separate
/// from the model so the domain stays framework-agnostic-ish
/// (colors are Material but carry no layout concerns).
class NotificationVisual {
  const NotificationVisual({
    required this.icon,
    required this.color,
    required this.sectionLabel,
  });

  final IconData icon;
  final Color color;

  /// Human label for accessibility / debugging, e.g. "Pedido web".
  final String sectionLabel;

  static NotificationVisual of(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.webOrder:
        return const NotificationVisual(
          icon: Icons.shopping_bag_rounded,
          color: AppTheme.success,
          sectionLabel: 'Pedido web',
        );
      case NotificationKind.fiado:
        return const NotificationVisual(
          icon: Icons.menu_book_rounded,
          color: Color(0xFF6D28D9), // purple-700
          sectionLabel: 'Fiado',
        );
      case NotificationKind.system:
        return const NotificationVisual(
          icon: Icons.inventory_2_rounded,
          color: AppTheme.primary,
          sectionLabel: 'Sistema',
        );
    }
  }
}

/// Date bucket for grouping in the activity feed.
enum NotificationDateBucket { today, yesterday, older }

/// Classify [when] relative to [now]. Pure so unit tests can feed
/// deterministic "now" values and assert the grouping.
NotificationDateBucket bucketFor(DateTime? when, {required DateTime now}) {
  if (when == null) return NotificationDateBucket.older;
  final localWhen = when.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final whenDay = DateTime(localWhen.year, localWhen.month, localWhen.day);
  final diffDays = today.difference(whenDay).inDays;
  if (diffDays <= 0) return NotificationDateBucket.today;
  if (diffDays == 1) return NotificationDateBucket.yesterday;
  return NotificationDateBucket.older;
}

String bucketLabel(NotificationDateBucket b) {
  switch (b) {
    case NotificationDateBucket.today:
      return 'Hoy';
    case NotificationDateBucket.yesterday:
      return 'Ayer';
    case NotificationDateBucket.older:
      return 'Más antiguas';
  }
}

/// Pretty-print a relative time delta. Returns empty string when
/// the timestamp is null — the caller should skip rendering.
String relativeTime(DateTime? when, {required DateTime now}) {
  if (when == null) return '';
  final d = now.difference(when.toLocal());
  if (d.inSeconds < 60) return 'hace segundos';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  if (d.inDays < 7) return 'hace ${d.inDays} d';
  return 'hace ${(d.inDays / 7).floor()} sem';
}
