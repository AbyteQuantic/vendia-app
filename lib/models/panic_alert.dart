// Spec: specs/057-panic-button-delivery/spec.md
//
// Modelo del histórico de alertas de pánico que muestra la pantalla de
// Seguridad. Parsing puro (fromApi) para poder testear sin red.

import 'package:flutter/material.dart';

class PanicDelivery {
  final String contactName;
  final String phoneNumber;
  final String method; // sms | whatsapp
  final String status; // sent | failed | skipped | pending
  final String? errorDetail;

  const PanicDelivery({
    required this.contactName,
    required this.phoneNumber,
    required this.method,
    required this.status,
    this.errorDetail,
  });

  static PanicDelivery fromApi(Map<String, dynamic> raw) => PanicDelivery(
        contactName: raw['contact_name']?.toString() ?? '',
        phoneNumber: raw['phone_number']?.toString() ?? '',
        method: raw['method']?.toString() ?? 'whatsapp',
        status: raw['status']?.toString() ?? 'pending',
        errorDetail: raw['error_detail']?.toString(),
      );

  /// Etiqueta en español del estado de entrega (modo USTED, claro para 50+).
  String get statusLabel {
    switch (status) {
      case 'sent':
        return 'Enviado';
      case 'failed':
        return 'No se pudo enviar';
      case 'skipped':
        return 'Canal sin configurar';
      default:
        return 'Pendiente';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'sent':
        return const Color(0xFF059669); // verde
      case 'failed':
        return const Color(0xFFDC2626); // rojo
      case 'skipped':
        return const Color(0xFFD97706); // ámbar
      default:
        return const Color(0xFF6B7280); // gris
    }
  }
}

class PanicAlert {
  final String id;
  final String message;
  final DateTime? triggeredAt;
  final int contactCount;
  final List<PanicDelivery> deliveries;

  const PanicAlert({
    required this.id,
    required this.message,
    required this.triggeredAt,
    required this.contactCount,
    required this.deliveries,
  });

  static PanicAlert fromApi(Map<String, dynamic> raw) {
    final rawDeliveries = raw['deliveries'];
    final deliveries = <PanicDelivery>[];
    if (rawDeliveries is List) {
      for (final d in rawDeliveries) {
        if (d is Map) {
          deliveries.add(PanicDelivery.fromApi(d.cast<String, dynamic>()));
        }
      }
    }
    return PanicAlert(
      id: raw['id']?.toString() ?? '',
      message: raw['message']?.toString() ?? '',
      triggeredAt: DateTime.tryParse(raw['triggered_at']?.toString() ?? ''),
      contactCount: (raw['contact_count'] as num?)?.toInt() ?? deliveries.length,
      deliveries: deliveries,
    );
  }
}
