// Spec: specs/042-modulo-eventos/spec.md
//
// Modelo inmutable del dominio "Eventos" (F042) — lo que el tendero
// organizador crea y la lista del Dashboard pinta. Espeja el modelo
// backend `Event` (internal/models/event.go) con los campos que la UI
// del MVP necesita.

/// Tipos, modalidades y estados — strings estables que espejan el backend.
class EventType {
  static const curso = 'curso';
  static const conferencia = 'conferencia';
  static const hackaton = 'hackaton';
  static const otro = 'otro';

  static const all = [curso, conferencia, hackaton, otro];

  /// Etiqueta en español para mostrar en la UI.
  static String label(String value) => switch (value) {
        curso => 'Curso',
        conferencia => 'Conferencia',
        hackaton => 'Hackatón',
        _ => 'Otro',
      };
}

class EventModality {
  static const presencial = 'presencial';
  static const virtual = 'virtual';
  static const hibrido = 'hibrido';

  static const all = [presencial, virtual, hibrido];

  static String label(String value) => switch (value) {
        presencial => 'Presencial',
        virtual => 'Virtual',
        hibrido => 'Híbrido',
        _ => value,
      };
}

class EventStatus {
  static const borrador = 'borrador';
  static const publicado = 'publicado';
  static const archivado = 'archivado';
  static const cancelado = 'cancelado';

  static String label(String value) => switch (value) {
        borrador => 'Borrador',
        publicado => 'Publicado',
        archivado => 'Archivado',
        cancelado => 'Cancelado',
        _ => value,
      };
}

/// Un evento del organizador. Inmutable.
class Event {
  final String id;
  final String type;
  final String title;
  final String description;
  final DateTime? startAt;
  final DateTime? endAt;
  final String modality;
  final String locationOrLink;

  /// Cupo máximo. 0 = sin límite.
  final int capacity;

  /// Precio de inscripción (entero en la moneda). 0 = gratis.
  final int price;

  /// Moneda del precio: 'COP' (default) o 'USD'.
  final String currency;

  final String status;
  final bool installmentsEnabled;
  final int installmentsCount;

  /// URLs de las piezas diseñadas (image_url de cada plantilla). Sirven para
  /// el preview del catálogo y para precargar el editor con la imagen actual.
  final String posterUrl;
  final String badgeUrl;
  final String certificateUrl;

  /// Métodos de pago que el organizador acepta para este evento (claves
  /// estables: efectivo/transferencia/tarjeta/otro). Se muestran al asistente.
  final List<String> enabledPaymentMethods;

  const Event({
    required this.id,
    this.type = EventType.otro,
    this.title = '',
    this.description = '',
    this.startAt,
    this.endAt,
    this.modality = EventModality.presencial,
    this.locationOrLink = '',
    this.capacity = 0,
    this.price = 0,
    this.currency = 'COP',
    this.status = EventStatus.borrador,
    this.installmentsEnabled = false,
    this.installmentsCount = 0,
    this.enabledPaymentMethods = const [],
    this.posterUrl = '',
    this.badgeUrl = '',
    this.certificateUrl = '',
  });

  /// True cuando el evento es gratuito.
  bool get isFree => price <= 0;

  /// True cuando el evento está visible en el catálogo público.
  bool get isPublished => status == EventStatus.publicado;

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      type: (json['type'] as String?) ?? EventType.otro,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      startAt: _parseDate(json['start_at']),
      endAt: _parseDate(json['end_at']),
      modality: (json['modality'] as String?) ?? EventModality.presencial,
      locationOrLink: (json['location_or_link'] as String?) ?? '',
      capacity: (json['capacity'] as num? ?? 0).toInt(),
      price: (json['price'] as num? ?? 0).toInt(),
      currency: (json['currency'] as String?) ?? 'COP',
      status: (json['status'] as String?) ?? EventStatus.borrador,
      installmentsEnabled: json['installments_enabled'] == true,
      installmentsCount: (json['installments_count'] as num? ?? 0).toInt(),
      enabledPaymentMethods:
          (json['enabled_payment_methods'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(growable: false),
      posterUrl: _templateUrl(json['poster_template']),
      badgeUrl: _templateUrl(json['badge_template']),
      certificateUrl: _templateUrl(json['certificate_template']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'description': description,
        if (startAt != null) 'start_at': startAt!.toIso8601String(),
        if (endAt != null) 'end_at': endAt!.toIso8601String(),
        'modality': modality,
        'location_or_link': locationOrLink,
        'capacity': capacity,
        'price': price,
        'currency': currency,
        'status': status,
        'installments_enabled': installmentsEnabled,
        'installments_count': installmentsCount,
        'enabled_payment_methods': enabledPaymentMethods,
      };

  Event copyWith({
    String? id,
    String? type,
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    String? modality,
    String? locationOrLink,
    int? capacity,
    int? price,
    String? currency,
    String? status,
    bool? installmentsEnabled,
    int? installmentsCount,
    List<String>? enabledPaymentMethods,
    String? posterUrl,
    String? badgeUrl,
    String? certificateUrl,
  }) {
    return Event(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      modality: modality ?? this.modality,
      locationOrLink: locationOrLink ?? this.locationOrLink,
      capacity: capacity ?? this.capacity,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      installmentsEnabled: installmentsEnabled ?? this.installmentsEnabled,
      installmentsCount: installmentsCount ?? this.installmentsCount,
      enabledPaymentMethods:
          enabledPaymentMethods ?? this.enabledPaymentMethods,
      posterUrl: posterUrl ?? this.posterUrl,
      badgeUrl: badgeUrl ?? this.badgeUrl,
      certificateUrl: certificateUrl ?? this.certificateUrl,
    );
  }
}

/// Extrae `image_url` de una plantilla (badge/certificate/poster) del JSON.
String _templateUrl(dynamic template) =>
    (template as Map<String, dynamic>?)?['image_url'] as String? ?? '';

/// Métodos de pago que el organizador puede habilitar para un evento. Claves
/// estables que espejan el backend; el cobro ocurre por fuera (VendIA conecta).
class EventPaymentMethod {
  static const efectivo = 'efectivo';
  static const transferencia = 'transferencia';
  static const tarjeta = 'tarjeta';
  static const otro = 'otro';

  static const all = [efectivo, transferencia, tarjeta, otro];

  static String label(String v) => switch (v) {
        efectivo => 'Efectivo',
        transferencia => 'Transferencia / Nequi / Daviplata',
        tarjeta => 'Tarjeta / PSE',
        otro => 'Otro',
        _ => v,
      };
}

/// Una fila del panel de inscritos del organizador (F042).
class EventRegistrationView {
  final String id;
  final String customerName;
  final String customerPhone;
  final String paymentStatus;
  final int amountPaid;
  final int price;
  final int balance;
  final bool checkedIn;
  final bool checkedOut;
  final bool certificateEligible;
  final bool certificateIssued;

  const EventRegistrationView({
    required this.id,
    this.customerName = '',
    this.customerPhone = '',
    this.paymentStatus = '',
    this.amountPaid = 0,
    this.price = 0,
    this.balance = 0,
    this.checkedIn = false,
    this.checkedOut = false,
    this.certificateEligible = false,
    this.certificateIssued = false,
  });

  bool get isConfirmed => paymentStatus == 'confirmed';

  /// True cuando el evento es de pago y aún queda saldo por cubrir.
  bool get hasBalance => !isConfirmed && balance > 0;

  factory EventRegistrationView.fromJson(Map<String, dynamic> json) {
    return EventRegistrationView(
      id: (json['id'] ?? '').toString(),
      customerName: (json['customer_name'] as String?) ?? '',
      customerPhone: (json['customer_phone'] as String?) ?? '',
      paymentStatus: (json['payment_status'] as String?) ?? '',
      amountPaid: (json['amount_paid'] as num? ?? 0).toInt(),
      price: (json['price'] as num? ?? 0).toInt(),
      balance: (json['balance'] as num? ?? 0).toInt(),
      checkedIn: json['checked_in'] == true,
      checkedOut: json['checked_out'] == true,
      certificateEligible: json['certificate_eligible'] == true,
      certificateIssued: json['certificate_issued'] == true,
    );
  }
}

/// Un comprobante/pago manual reportado por un asistente, en la bandeja de
/// revisión del organizador (F042).
class EventPaymentView {
  final String id;
  final String registrationId;
  final String customerName;
  final int amount;
  final String proofUrl;
  final String note;
  final String status;

  const EventPaymentView({
    required this.id,
    this.registrationId = '',
    this.customerName = '',
    this.amount = 0,
    this.proofUrl = '',
    this.note = '',
    this.status = '',
  });

  bool get hasProof => proofUrl.isNotEmpty;

  factory EventPaymentView.fromJson(Map<String, dynamic> json) {
    return EventPaymentView(
      id: (json['id'] ?? '').toString(),
      registrationId: (json['registration_id'] as String?) ?? '',
      customerName: (json['customer_name'] as String?) ?? '',
      amount: (json['amount'] as num? ?? 0).toInt(),
      proofUrl: (json['proof_url'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
