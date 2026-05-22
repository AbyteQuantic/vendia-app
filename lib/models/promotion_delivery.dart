// Spec: specs/033-difusion-promociones/spec.md
//
// Modelo inmutable de un envío de promoción a un cliente (F033).
//
// Un [PromotionDelivery] es una fila de la tabla `promotion_deliveries`
// (plan §3): representa que la promoción X se le va a enviar / se le
// envió al cliente Y por el canal Z. La cola de WhatsApp en modo
// express (spec §4.5) consume estos registros uno por uno.
//
// FSM del estado (plan §4):
//   queued ──(el dueño tocó "enviar" en WhatsApp)──▶ sent
//   queued ──(el dueño tocó "saltar")─────────────▶ skipped
//
// El `(promotionId, customerId, channel)` es único en backend para
// evitar reenviar al mismo cliente en la misma promo (spec AC-06).

/// Canal por el que se hace llegar una promoción.
enum PromotionChannel {
  whatsapp,
  link,
  qr,
  manual;

  /// Valor que viaja al backend.
  String get wire => name;

  /// Parsea el string del backend; cualquier valor desconocido cae a
  /// `manual` de forma defensiva.
  static PromotionChannel fromWire(String? raw) {
    switch (raw) {
      case 'whatsapp':
        return PromotionChannel.whatsapp;
      case 'link':
        return PromotionChannel.link;
      case 'qr':
        return PromotionChannel.qr;
      case 'manual':
      default:
        return PromotionChannel.manual;
    }
  }
}

/// Estado de un envío dentro de la cola de difusión.
enum PromotionDeliveryStatus {
  queued,
  sent,
  skipped;

  String get wire => name;

  /// Etiqueta en español para la UI.
  String get label {
    switch (this) {
      case PromotionDeliveryStatus.queued:
        return 'En cola';
      case PromotionDeliveryStatus.sent:
        return 'Enviado';
      case PromotionDeliveryStatus.skipped:
        return 'Omitido';
    }
  }

  static PromotionDeliveryStatus fromWire(String? raw) {
    switch (raw) {
      case 'sent':
        return PromotionDeliveryStatus.sent;
      case 'skipped':
        return PromotionDeliveryStatus.skipped;
      case 'queued':
      default:
        return PromotionDeliveryStatus.queued;
    }
  }
}

/// Un envío de promoción a un cliente.
class PromotionDelivery {
  /// UUID del registro de delivery.
  final String id;

  /// UUID de la promoción.
  final String promotionId;

  /// UUID del cliente destinatario.
  final String customerId;

  /// Nombre del cliente — denormalizado para pintar la cola y el log.
  final String customerName;

  /// Teléfono del cliente (formato como viene de F030). Puede ir vacío.
  final String customerPhone;

  final PromotionChannel channel;
  final PromotionDeliveryStatus status;

  /// Mensaje pre-personalizado para este cliente — el backend pre-genera
  /// el texto con `{nombre}`/`{primer_nombre}` ya sustituidos (plan D10).
  /// Si viene vacío el cliente lo genera en el dispositivo.
  final String renderedMessage;

  final DateTime? sentAt;
  final DateTime? visitedAt;

  const PromotionDelivery({
    this.id = '',
    required this.promotionId,
    required this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.channel = PromotionChannel.whatsapp,
    this.status = PromotionDeliveryStatus.queued,
    this.renderedMessage = '',
    this.sentAt,
    this.visitedAt,
  });

  /// True cuando el cliente abrió el link público de la promo.
  bool get wasVisited => visitedAt != null;

  factory PromotionDelivery.fromJson(Map<String, dynamic> json) {
    final rawCustomer = json['customer'];
    String customerName = (json['customer_name'] as String?) ?? '';
    String customerPhone = (json['customer_phone'] as String?) ?? '';
    if (rawCustomer is Map<String, dynamic>) {
      if (customerName.isEmpty) {
        customerName = (rawCustomer['name'] as String?) ?? '';
      }
      if (customerPhone.isEmpty) {
        customerPhone = (rawCustomer['phone'] as String?) ?? '';
      }
    }
    return PromotionDelivery(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      promotionId: (json['promotion_id'] ?? '').toString(),
      customerId: (json['customer_id'] ?? '').toString(),
      customerName: customerName,
      customerPhone: customerPhone,
      channel: PromotionChannel.fromWire(json['channel'] as String?),
      status:
          PromotionDeliveryStatus.fromWire(json['status'] as String?),
      renderedMessage: (json['rendered_message'] as String?) ?? '',
      sentAt: _parseDate(json['sent_at']),
      visitedAt: _parseDate(json['visited_at']),
    );
  }

  PromotionDelivery copyWith({
    String? id,
    String? promotionId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    PromotionChannel? channel,
    PromotionDeliveryStatus? status,
    String? renderedMessage,
    DateTime? sentAt,
    DateTime? visitedAt,
  }) {
    return PromotionDelivery(
      id: id ?? this.id,
      promotionId: promotionId ?? this.promotionId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      channel: channel ?? this.channel,
      status: status ?? this.status,
      renderedMessage: renderedMessage ?? this.renderedMessage,
      sentAt: sentAt ?? this.sentAt,
      visitedAt: visitedAt ?? this.visitedAt,
    );
  }
}

/// Parsea una fecha ISO-8601 de forma defensiva — null ante cualquier
/// valor ausente, vacío o malformado. Nunca lanza.
DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
