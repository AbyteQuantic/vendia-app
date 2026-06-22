// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/foundation.dart';

/// Task — una tarea pendiente DERIVADA de una entidad real (pedido, mesa,
/// mandado, stock). Value object inmutable. El id "{kind}:{source}" es la clave
/// anti-duplicado. Spec 078.
@immutable
class Task {
  final String id;
  final String kind;
  final String sourceId;
  final String title;
  final String subtitle;
  final String urgency; // critical | high | normal | low
  final int count; // tareas agregadas (ej "5 por reordenar")
  final String actionLabel;
  final String deepLink;
  final double amount;
  final String sessionToken; // cuenta de mesa: token para la pantalla de cobro
  final DateTime? createdAt;

  const Task({
    required this.id,
    required this.kind,
    required this.sourceId,
    required this.title,
    required this.subtitle,
    required this.urgency,
    required this.actionLabel,
    required this.deepLink,
    this.count = 0,
    this.amount = 0,
    this.sessionToken = '',
    this.createdAt,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: (j['id'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        sourceId: (j['source_id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        urgency: (j['urgency'] ?? 'normal').toString(),
        actionLabel: (j['action_label'] ?? '').toString(),
        deepLink: (j['deep_link'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        sessionToken: (j['session_token'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );

  bool get isUrgent => urgency == 'critical' || urgency == 'high';
  bool get isActionable => isUrgent || urgency == 'normal';

  /// Tareas AGREGADAS (sin entidad propia) que se pueden posponer.
  bool get isDismissable => kind == 'reorder' || kind == 'perishable';
}
