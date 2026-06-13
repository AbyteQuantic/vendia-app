// Spec: specs/031-cotizaciones/spec.md
//
// Modelo inmutable de una cotización (F031).
//
// Una [Quote] es la propuesta de precio que el dueño arma para un
// cliente antes de la venta: folio secuencial, cliente (F030), líneas
// de items, descuento, impuestos (F023), vigencia y nota.
//
// Espejo del modelo backend `Quote` (plan §3). Los estados válidos y
// las acciones contextuales (enviar / convertir) viven en [QuoteStatus].

import 'quote_item.dart';

/// Estados del ciclo de vida de una cotización — FSM del plan §3 (AC-05).
///
/// `borrador` → `enviada` → `aprobada` → `convertida`
///                       ↘ `rechazada`
///                       ↘ `vencida`   (automático tras `valid_until`)
/// `borrador`/`enviada` editables; al editar una `enviada` se crea V2 y
/// la v1 queda `reemplazada`.
enum QuoteStatus {
  borrador,
  enviada,
  aprobada,
  rechazada,
  vencida,
  convertida,
  reemplazada;

  /// Parsea el string del backend. Cualquier valor desconocido cae a
  /// `borrador` de forma defensiva — nunca lanza.
  static QuoteStatus fromWire(String? raw) {
    switch (raw) {
      case 'enviada':
        return QuoteStatus.enviada;
      case 'aprobada':
        return QuoteStatus.aprobada;
      case 'rechazada':
        return QuoteStatus.rechazada;
      case 'vencida':
        return QuoteStatus.vencida;
      case 'convertida':
        return QuoteStatus.convertida;
      case 'reemplazada':
        return QuoteStatus.reemplazada;
      case 'borrador':
      default:
        return QuoteStatus.borrador;
    }
  }

  /// Valor que viaja al backend.
  String get wire => name;

  /// Etiqueta en español para la UI.
  String get label {
    switch (this) {
      case QuoteStatus.borrador:
        return 'Borrador';
      case QuoteStatus.enviada:
        return 'Enviada';
      case QuoteStatus.aprobada:
        return 'Aprobada';
      case QuoteStatus.rechazada:
        return 'Rechazada';
      case QuoteStatus.vencida:
        return 'Vencida';
      case QuoteStatus.convertida:
        return 'Convertida';
      case QuoteStatus.reemplazada:
        return 'Reemplazada';
    }
  }

  /// Solo una cotización en `borrador` puede enviarse.
  bool get canSend => this == QuoteStatus.borrador;

  /// Solo una cotización `aprobada` puede convertirse en venta.
  bool get canConvert => this == QuoteStatus.aprobada;

  /// `borrador` y `enviada` son editables (AC-11).
  bool get canEdit =>
      this == QuoteStatus.borrador || this == QuoteStatus.enviada;
}

/// Una cotización completa con sus líneas.
class Quote {
  /// UUID de la cotización. Vacío solo en estados transitorios.
  final String id;

  /// Folio secuencial — ej. `COT-2026-0001` o `COT-2026-0001-V2`.
  final String folio;

  final QuoteStatus status;

  /// UUID del cliente asociado (F030 — obligatorio).
  final String customerId;

  /// Nombre del cliente — denormalizado para pintar la lista sin un
  /// fetch extra por fila.
  final String customerName;

  /// Teléfono del cliente — usado para abrir WhatsApp dirigido a su número
  /// (`wa.me/<phone>?text=…`, que SÍ precarga el mensaje en iOS; el
  /// `wa.me/?text=` sin número no lo hace). Vacío si el cliente no tiene.
  final String customerPhone;

  /// Líneas de la cotización.
  final List<QuoteItem> items;

  /// Descuento total aplicado a la cotización (en COP).
  final double discountTotal;

  /// Tasa de impuesto (ej. 0.19). 0 cuando F023 está OFF.
  final double taxRate;

  final double subtotal;
  final double taxAmount;
  final double total;

  /// Fecha de vigencia — pasada esta fecha sin respuesta pasa a vencida.
  final DateTime? validUntil;

  /// Nota libre opcional.
  final String note;

  /// Token público — alimenta el link `tienda.vendia.store/c/<token>`.
  final String publicToken;

  /// UUID de la venta generada al convertir. Null si aún no se convirtió.
  final String? saleId;

  final DateTime? sentAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Quote({
    required this.id,
    this.folio = '',
    this.status = QuoteStatus.borrador,
    required this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.items = const [],
    this.discountTotal = 0,
    this.taxRate = 0,
    this.subtotal = 0,
    this.taxAmount = 0,
    this.total = 0,
    this.validUntil,
    this.note = '',
    this.publicToken = '',
    this.saleId,
    this.sentAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Número de líneas de la cotización.
  int get itemCount => items.length;

  /// URL pública de la cotización para WhatsApp / compartir.
  /// Vacío si aún no tiene token (cotización sin guardar).
  String publicUrl(String baseHost) {
    if (publicToken.isEmpty) return '';
    return '$baseHost/c/$publicToken';
  }

  factory Quote.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final rawCustomer = json['customer'];
    String customerName = (json['customer_name'] as String?) ?? '';
    if (customerName.isEmpty && rawCustomer is Map<String, dynamic>) {
      customerName = (rawCustomer['name'] as String?) ?? '';
    }
    String customerId = (json['customer_id'] ?? '').toString();
    if (customerId.isEmpty && rawCustomer is Map<String, dynamic>) {
      customerId = (rawCustomer['id'] ?? '').toString();
    }
    String customerPhone = (json['customer_phone'] as String?) ?? '';
    if (customerPhone.isEmpty && rawCustomer is Map<String, dynamic>) {
      customerPhone = (rawCustomer['phone'] as String?) ?? '';
    }
    return Quote(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      folio: (json['folio'] as String?) ?? '',
      status: QuoteStatus.fromWire(json['status'] as String?),
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(QuoteItem.fromJson)
          .toList(growable: false),
      discountTotal: (json['discount_total'] as num? ?? 0).toDouble(),
      taxRate: (json['tax_rate'] as num? ?? 0).toDouble(),
      subtotal: (json['subtotal'] as num? ?? 0).toDouble(),
      taxAmount: (json['tax_amount'] as num? ?? 0).toDouble(),
      total: (json['total'] as num? ?? 0).toDouble(),
      validUntil: _parseDate(json['valid_until']),
      note: (json['note'] as String?) ?? '',
      publicToken: (json['public_token'] as String?) ?? '',
      saleId: (json['sale_id'] == null || json['sale_id'] == '')
          ? null
          : json['sale_id'].toString(),
      sentAt: _parseDate(json['sent_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  /// Payload de creación / edición — POST/PATCH /api/v1/quotes.
  Map<String, dynamic> toJson() => {
        'customer_id': customerId,
        'items': items.map((e) => e.toJson()).toList(),
        'discount_total': discountTotal,
        'tax_rate': taxRate,
        if (validUntil != null)
          'valid_until': validUntil!.toIso8601String(),
        'note': note,
      };

  Quote copyWith({
    String? id,
    String? folio,
    QuoteStatus? status,
    String? customerId,
    String? customerName,
    List<QuoteItem>? items,
    double? discountTotal,
    double? taxRate,
    double? subtotal,
    double? taxAmount,
    double? total,
    DateTime? validUntil,
    String? note,
    String? publicToken,
    String? saleId,
    DateTime? sentAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Quote(
      id: id ?? this.id,
      folio: folio ?? this.folio,
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      items: items ?? this.items,
      discountTotal: discountTotal ?? this.discountTotal,
      taxRate: taxRate ?? this.taxRate,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      validUntil: validUntil ?? this.validUntil,
      note: note ?? this.note,
      publicToken: publicToken ?? this.publicToken,
      saleId: saleId ?? this.saleId,
      sentAt: sentAt ?? this.sentAt,
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
