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

  /// Estado DERIVADO (no lo guarda el backend): un evento publicado cuyo fin ya
  /// pasó. Se calcula en la app desde `endAt` para reflejar que concluyó, igual
  /// que el catálogo público. Ver Event.displayStatus / Event.isFinished.
  static const finalizado = 'finalizado';

  static String label(String value) => switch (value) {
        borrador => 'Borrador',
        publicado => 'Publicado',
        archivado => 'Archivado',
        cancelado => 'Cancelado',
        finalizado => 'Finalizado',
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

  /// Ubicación física (eventos presenciales): ciudad e indicaciones/edificio.
  final String city;
  final String locationNotes;

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

  /// Datos de pago por método (instrucciones + QR) que ve el asistente.
  final List<EventPaymentDetail> paymentDetails;

  /// Texto editable del certificado (la app compone el resto con defaults).
  final EventCertificateConfig certificateConfig;

  const Event({
    required this.id,
    this.type = EventType.otro,
    this.title = '',
    this.description = '',
    this.startAt,
    this.endAt,
    this.modality = EventModality.presencial,
    this.locationOrLink = '',
    this.city = '',
    this.locationNotes = '',
    this.capacity = 0,
    this.price = 0,
    this.currency = 'COP',
    this.status = EventStatus.borrador,
    this.installmentsEnabled = false,
    this.installmentsCount = 0,
    this.enabledPaymentMethods = const [],
    this.paymentDetails = const [],
    this.certificateConfig = const EventCertificateConfig(),
    this.posterUrl = '',
    this.badgeUrl = '',
    this.certificateUrl = '',
  });

  /// True cuando el evento es gratuito.
  bool get isFree => price <= 0;

  /// True cuando el evento está visible en el catálogo público.
  bool get isPublished => status == EventStatus.publicado;

  /// True cuando el evento ya terminó: publicado y con `endAt` en el pasado.
  /// Estado DERIVADO (no almacenado), calculado desde la fecha de fin, para
  /// reflejar en la UI que concluyó — consistente con el catálogo público.
  bool get isFinished {
    if (status != EventStatus.publicado || endAt == null) return false;
    return DateTime.now().isAfter(endAt!);
  }

  /// Estado a MOSTRAR en la UI: 'finalizado' si ya terminó; si no, el `status`
  /// real del backend. Úsalo para el badge en vez de `status` crudo.
  String get displayStatus =>
      isFinished ? EventStatus.finalizado : status;

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
      city: (json['city'] as String?) ?? '',
      locationNotes: (json['location_notes'] as String?) ?? '',
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
      paymentDetails: (json['payment_details'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EventPaymentDetail.fromJson)
          .toList(growable: false),
      certificateConfig: EventCertificateConfig.fromJson(
          (json['certificate_config'] as Map<String, dynamic>?) ?? const {}),
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
        'city': city,
        'location_notes': locationNotes,
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
    String? city,
    String? locationNotes,
    int? capacity,
    int? price,
    String? currency,
    String? status,
    bool? installmentsEnabled,
    int? installmentsCount,
    List<String>? enabledPaymentMethods,
    List<EventPaymentDetail>? paymentDetails,
    EventCertificateConfig? certificateConfig,
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
      city: city ?? this.city,
      locationNotes: locationNotes ?? this.locationNotes,
      capacity: capacity ?? this.capacity,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      installmentsEnabled: installmentsEnabled ?? this.installmentsEnabled,
      installmentsCount: installmentsCount ?? this.installmentsCount,
      enabledPaymentMethods:
          enabledPaymentMethods ?? this.enabledPaymentMethods,
      paymentDetails: paymentDetails ?? this.paymentDetails,
      certificateConfig: certificateConfig ?? this.certificateConfig,
      posterUrl: posterUrl ?? this.posterUrl,
      badgeUrl: badgeUrl ?? this.badgeUrl,
      certificateUrl: certificateUrl ?? this.certificateUrl,
    );
  }
}

/// Datos de pago de UN método: instrucciones (número/cuenta) + QR opcional.
class EventPaymentDetail {
  final String method;
  final String instructions;
  final String qrImageUrl;

  const EventPaymentDetail({
    required this.method,
    this.instructions = '',
    this.qrImageUrl = '',
  });

  factory EventPaymentDetail.fromJson(Map<String, dynamic> json) =>
      EventPaymentDetail(
        method: (json['method'] as String?) ?? '',
        instructions: (json['instructions'] as String?) ?? '',
        qrImageUrl: (json['qr_image_url'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'method': method,
        'instructions': instructions,
        'qr_image_url': qrImageUrl,
      };

  bool get isEmpty => instructions.trim().isEmpty && qrImageUrl.isEmpty;
}

/// Texto editable del certificado. Campos vacíos → la app usa defaults.
class EventCertificateConfig {
  final String title;
  final String intro;
  final String body;
  final String signatory;
  final String footer;
  final String signatureImage;
  final String logoImage;

  /// Distingue "logo nunca configurado" (→ usar el del negocio por defecto) de
  /// "el organizador lo quitó a propósito" (→ no reinyectarlo).
  final bool logoCleared;

  /// Posición/tamaño de cada elemento (claves: title/intro/name/body/date/
  /// signatory/signature/logo/qr). Vacío → layout por defecto.
  final Map<String, CertElementPos> layout;

  const EventCertificateConfig({
    this.title = '',
    this.intro = '',
    this.body = '',
    this.signatory = '',
    this.footer = '',
    this.signatureImage = '',
    this.logoImage = '',
    this.logoCleared = false,
    this.layout = const {},
  });

  factory EventCertificateConfig.fromJson(Map<String, dynamic> json) {
    final rawLayout = (json['layout'] as Map<String, dynamic>?) ?? const {};
    return EventCertificateConfig(
      title: (json['title'] as String?) ?? '',
      intro: (json['intro'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      signatory: (json['signatory'] as String?) ?? '',
      footer: (json['footer'] as String?) ?? '',
      signatureImage: (json['signature_image'] as String?) ?? '',
      logoImage: (json['logo_image'] as String?) ?? '',
      logoCleared: json['logo_cleared'] == true,
      layout: rawLayout.map((k, v) =>
          MapEntry(k, CertElementPos.fromJson((v as Map).cast<String, dynamic>()))),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'intro': intro,
        'body': body,
        'signatory': signatory,
        'footer': footer,
        'signature_image': signatureImage,
        'logo_image': logoImage,
        'logo_cleared': logoCleared,
        'layout': layout.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// Posición normalizada (0..1) y tamaño relativo de un elemento del diploma.
class CertElementPos {
  final double x;
  final double y;
  final double scale;
  final bool hidden;

  const CertElementPos({
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 0.04,
    this.hidden = false,
  });

  factory CertElementPos.fromJson(Map<String, dynamic> json) => CertElementPos(
        x: (json['x'] as num? ?? 0.5).toDouble(),
        y: (json['y'] as num? ?? 0.5).toDouble(),
        scale: (json['scale'] as num? ?? 0.04).toDouble(),
        hidden: json['hidden'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'scale': scale, 'hidden': hidden};

  CertElementPos copyWith({double? x, double? y, double? scale, bool? hidden}) =>
      CertElementPos(
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        hidden: hidden ?? this.hidden,
      );
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
/// Resumen del cronograma de cuotas de un inscrito (derivado por el backend:
/// 1ª al inscribirse, resto hasta el inicio). El organizador lo ve en el panel
/// de inscritos para saber a quién se le vence o se le venció una cuota.
class EventInstallmentPlan {
  final int count;
  final int paidCount;
  final int remainingCount;
  final int overdueCount;
  final int overdueAmount;
  final int nextDueNumber;
  final DateTime? nextDueDate;
  final int nextDueAmount;
  final DateTime? finalDueDate;

  const EventInstallmentPlan({
    this.count = 0,
    this.paidCount = 0,
    this.remainingCount = 0,
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.nextDueNumber = 0,
    this.nextDueDate,
    this.nextDueAmount = 0,
    this.finalDueDate,
  });

  bool get hasOverdue => overdueCount > 0;

  factory EventInstallmentPlan.fromJson(Map<String, dynamic> json) {
    return EventInstallmentPlan(
      count: (json['count'] as num? ?? 0).toInt(),
      paidCount: (json['paid_count'] as num? ?? 0).toInt(),
      remainingCount: (json['remaining_count'] as num? ?? 0).toInt(),
      overdueCount: (json['overdue_count'] as num? ?? 0).toInt(),
      overdueAmount: (json['overdue_amount'] as num? ?? 0).toInt(),
      nextDueNumber: (json['next_due_number'] as num? ?? 0).toInt(),
      nextDueDate: _parseDate(json['next_due_date']),
      nextDueAmount: (json['next_due_amount'] as num? ?? 0).toInt(),
      finalDueDate: _parseDate(json['final_due_date']),
    );
  }
}

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
  final int? seatNumber;
  final bool certificateEligible;
  final bool certificateIssued;

  /// Cronograma de cuotas del inscrito (null si el evento no admite cuotas o ya
  /// no queda saldo).
  final EventInstallmentPlan? installments;

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
    this.seatNumber,
    this.certificateEligible = false,
    this.certificateIssued = false,
    this.installments,
  });

  /// Copia con una silla distinta (para refrescar la UI tras asignar/liberar).
  EventRegistrationView copyWithSeat(int? seat) => EventRegistrationView(
        id: id,
        customerName: customerName,
        customerPhone: customerPhone,
        paymentStatus: paymentStatus,
        amountPaid: amountPaid,
        price: price,
        balance: balance,
        checkedIn: checkedIn,
        checkedOut: checkedOut,
        seatNumber: seat,
        certificateEligible: certificateEligible,
        certificateIssued: certificateIssued,
        installments: installments,
      );

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
      seatNumber: (json['seat_number'] as num?)?.toInt(),
      certificateEligible: json['certificate_eligible'] == true,
      certificateIssued: json['certificate_issued'] == true,
      installments: json['installments'] is Map<String, dynamic>
          ? EventInstallmentPlan.fromJson(
              json['installments'] as Map<String, dynamic>)
          : null,
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
