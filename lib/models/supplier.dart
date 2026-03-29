/// Supplier model for VendIA POS system.
/// Represents a product supplier/distributor with WhatsApp contact.
class Supplier {
  final String uuid;
  final String companyName;
  final String contactName;
  final String phone;
  final String? emoji; // Category emoji (🥤, 🍺, 🥛)
  final DateTime createdAt;
  final int? serverId;

  Supplier({
    required this.uuid,
    required this.companyName,
    required this.contactName,
    required this.phone,
    this.emoji,
    DateTime? createdAt,
    this.serverId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// WhatsApp deep link for quick messaging
  String get whatsappLink => 'https://wa.me/57$phone';

  /// Pre-built WhatsApp order message
  String orderMessage(String productName, int quantity) =>
      'Hola $contactName, por favor en mi pedido de mañana me incluyes '
      '$quantity unidades de $productName. Gracias.';

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      uuid: json['uuid'] as String,
      companyName: json['company_name'] as String,
      contactName: json['contact_name'] as String,
      phone: json['phone'] as String,
      emoji: json['emoji'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      serverId: json['id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'company_name': companyName,
        'contact_name': contactName,
        'phone': phone,
        'emoji': emoji,
      };
}
