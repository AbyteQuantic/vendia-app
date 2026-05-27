// Spec: specs/F38-notifications-deeplink/spec.md
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Semantic category for a notification.
///
/// The backend persists a free-form `type` string on each row
/// (`online_order`, `fiado_accepted`, `fiado_cancelled`,
/// `partial_payment`, `waiter_call`, `info`, …). The activity
/// feed buckets them into kinds, each bound to its own color +
/// icon language so the cashier can scan the list at a glance
/// without reading the text.
///
/// New kinds added in F38:
///   - [tableCall]      — Mesa llamando al mesero
///   - [partialPayment] — Cliente registró abono por confirmar
enum NotificationKind {
  /// Web orders flowing in from the public catalog. Routed to the
  /// online orders screen on tap.
  webOrder,

  /// Fiado lifecycle events: handshake accepted, canceled, paid,
  /// debt added. Routed to the Cuaderno on tap.
  fiado,

  /// A bar/restaurant table is calling the waiter
  /// (`POST /api/v1/public/table-sessions/:token/call-waiter`).
  /// Routed to the Mesas screen — the cashier opens the specific
  /// table from the live list.
  tableCall,

  /// A customer at a live table sent an abono (transfer + receipt
  /// or cash pending scan). Pending confirmation by the tendero.
  /// Routed to the Mesas screen with an instructional snackbar.
  partialPayment,

  /// Everything else: inventory alerts, generic system messages,
  /// `info` and unknown `type` values. Non-routable by default.
  system,
}

/// A single item rendered by [NotificationCenterSheet].
///
/// Intentionally kept as a value object so the categorization logic
/// is pure and unit-testable ([fromApi]). The backend contract is
/// `{id, type, title, body, is_read, created_at, data}`.
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
    this.paymentId,
    this.tableLabel,
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
  /// `data` JSON payload. The backend populates them per kind:
  ///   - webOrder       → orderId
  ///   - fiado*         → fiadoId
  ///   - tableCall      → orderId + tableLabel
  ///   - partialPayment → orderId + paymentId + tableLabel
  /// Older rows (pre-F38) won't have them — `null` is valid.
  final String? orderId;
  final String? fiadoId;
  final String? paymentId;
  final String? tableLabel;

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
    if (t == 'waiter_call' || t == 'mesa_llamada') {
      return NotificationKind.tableCall;
    }
    if (t == 'partial_payment' || t == 'abono_pendiente') {
      return NotificationKind.partialPayment;
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
    // links (order_id / fiado_id / payment_id / table_label).
    // Treat it as opaque: if the shape isn't a Map we silently
    // drop it rather than crashing.
    String? orderId;
    String? fiadoId;
    String? paymentId;
    String? tableLabel;
    final data = raw['data'];
    if (data is Map) {
      orderId = data['order_id']?.toString() ?? data['order_uuid']?.toString();
      fiadoId = data['fiado_id']?.toString() ?? data['fiado_token']?.toString();
      paymentId = data['payment_id']?.toString();
      tableLabel = data['table_label']?.toString();
    }

    return AppNotification(
      id: id,
      kind: kindFromType(raw['type']?.toString()),
      title: title,
      body: raw['body']?.toString() ?? '',
      isRead: raw['is_read'] == true,
      createdAt: _parseDate(raw['created_at']),
      rawType: raw['type']?.toString() ?? '',
      orderId: _emptyToNull(orderId),
      fiadoId: _emptyToNull(fiadoId),
      paymentId: _emptyToNull(paymentId),
      tableLabel: _emptyToNull(tableLabel),
    );
  }

  static String? _emptyToNull(String? v) =>
      (v == null || v.isEmpty) ? null : v;

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
      case NotificationKind.tableCall:
        return const NotificationVisual(
          icon: Icons.notifications_active_rounded,
          color: Color(0xFFEA580C), // orange-600 — urgencia de servicio
          sectionLabel: 'Mesa',
        );
      case NotificationKind.partialPayment:
        return const NotificationVisual(
          icon: Icons.payments_rounded,
          color: Color(0xFF0891B2), // cyan-600 — dinero/transferencia
          sectionLabel: 'Abono',
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
