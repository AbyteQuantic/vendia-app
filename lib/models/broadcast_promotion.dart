// Spec: specs/033-difusion-promociones/spec.md
//
// Modelo inmutable de una promoción de difusión (F033).
//
// Una [BroadcastPromotion] es la "campaña" que el dueño arma para
// avisarles a sus clientes: título, descripción, foto, vigencia, items
// en oferta opcionales, plantilla de mensaje con placeholders y
// programación de envío. Espejo del modelo backend `Promotion`
// (plan §3).
//
// NOTA — convivencia con el módulo legacy: el archivo `promotion.dart`
// ya define un `Promotion` distinto (las combo-promos de las migraciones
// 018-019). Para no romper ese módulo (spec AC-10) el modelo de F033
// vive aparte como `BroadcastPromotion`.
//
// El link público se construye con `tienda.vendia.store/p/<token>`
// (plan §4 — mismo patrón que `/c/<token>` de F031).

import 'promotion_item.dart';

/// Estado derivado de la vigencia + la programación de una promoción.
enum BroadcastPromotionState {
  /// `scheduled_for` en el futuro — la cola aún no debe abrirse.
  scheduled,

  /// Vigencia en curso (`valid_from <= now <= valid_until`).
  active,

  /// `valid_until` ya pasó.
  expired;

  /// Etiqueta en español para chips y filtros.
  String get label {
    switch (this) {
      case BroadcastPromotionState.scheduled:
        return 'Programada';
      case BroadcastPromotionState.active:
        return 'Activa';
      case BroadcastPromotionState.expired:
        return 'Vencida';
    }
  }
}

/// Una promoción de difusión completa con sus items en oferta.
class BroadcastPromotion {
  /// UUID de la promoción. Vacío solo en estados transitorios.
  final String id;

  final String title;
  final String description;

  /// URL de la foto/banner — subida o generada con IA. Puede ir vacía.
  final String imageUrl;

  /// Cupón informativo (ej. "PROMO20"). Sin validación en POS — F035.
  final String couponCode;

  final DateTime? validFrom;
  final DateTime? validUntil;

  /// Plantilla del mensaje de WhatsApp con placeholders `{nombre}` /
  /// `{primer_nombre}` (spec §4.5, mejora 2).
  final String messageTemplate;

  /// Momento programado de envío. Null → "enviar ahora" (spec §4.5,
  /// mejora 5). Cuando llega la hora el backend dispara el push.
  final DateTime? scheduledFor;

  /// Token público — alimenta `tienda.vendia.store/p/<token>`.
  final String publicToken;

  /// Número de visitas al link público (analytics básica).
  final int visitCount;

  /// Items en oferta — opcional (spec §4 "Crear promoción").
  final List<PromotionItem> items;

  /// Total de clientes a los que se les creó un delivery.
  final int audienceCount;

  /// Total de deliveries en estado `sent`.
  final int sentCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BroadcastPromotion({
    this.id = '',
    this.title = '',
    this.description = '',
    this.imageUrl = '',
    this.couponCode = '',
    this.validFrom,
    this.validUntil,
    this.messageTemplate = '',
    this.scheduledFor,
    this.publicToken = '',
    this.visitCount = 0,
    this.items = const [],
    this.audienceCount = 0,
    this.sentCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Estado derivado a partir de la fecha [now] (inyectable para tests).
  BroadcastPromotionState stateAt(DateTime now) {
    if (scheduledFor != null && scheduledFor!.isAfter(now)) {
      return BroadcastPromotionState.scheduled;
    }
    if (validUntil != null && validUntil!.isBefore(now)) {
      return BroadcastPromotionState.expired;
    }
    return BroadcastPromotionState.active;
  }

  /// Estado derivado usando la hora actual del dispositivo.
  BroadcastPromotionState get state => stateAt(DateTime.now());

  /// True cuando la promoción ya tiene token público válido.
  bool get hasPublicLink => publicToken.isNotEmpty;

  /// URL pública de la promoción para WhatsApp / compartir.
  /// Vacío si aún no tiene token (promoción sin guardar).
  String publicUrl(String baseHost) {
    if (publicToken.isEmpty) return '';
    return '$baseHost/p/$publicToken';
  }

  factory BroadcastPromotion.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return BroadcastPromotion(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      imageUrl: (json['image_url'] as String?) ?? '',
      couponCode: (json['coupon_code'] as String?) ?? '',
      validFrom: _parseDate(json['valid_from']),
      validUntil: _parseDate(json['valid_until']),
      messageTemplate: (json['message_template'] as String?) ?? '',
      scheduledFor: _parseDate(json['scheduled_for']),
      publicToken: (json['public_token'] as String?) ?? '',
      visitCount: (json['visit_count'] as num? ?? 0).toInt(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(PromotionItem.fromJson)
          .toList(growable: false),
      audienceCount: (json['audience_count'] as num? ?? 0).toInt(),
      sentCount: (json['sent_count'] as num? ?? 0).toInt(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  /// Payload de creación / edición — POST/PATCH /api/v1/promotions.
  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        if (imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (couponCode.isNotEmpty) 'coupon_code': couponCode,
        if (validFrom != null)
          'valid_from': validFrom!.toIso8601String(),
        if (validUntil != null)
          'valid_until': validUntil!.toIso8601String(),
        'message_template': messageTemplate,
        if (scheduledFor != null)
          'scheduled_for': scheduledFor!.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
      };

  BroadcastPromotion copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    String? couponCode,
    DateTime? validFrom,
    DateTime? validUntil,
    String? messageTemplate,
    DateTime? scheduledFor,
    String? publicToken,
    int? visitCount,
    List<PromotionItem>? items,
    int? audienceCount,
    int? sentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearScheduledFor = false,
  }) {
    return BroadcastPromotion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      couponCode: couponCode ?? this.couponCode,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      messageTemplate: messageTemplate ?? this.messageTemplate,
      scheduledFor:
          clearScheduledFor ? null : (scheduledFor ?? this.scheduledFor),
      publicToken: publicToken ?? this.publicToken,
      visitCount: visitCount ?? this.visitCount,
      items: items ?? this.items,
      audienceCount: audienceCount ?? this.audienceCount,
      sentCount: sentCount ?? this.sentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
