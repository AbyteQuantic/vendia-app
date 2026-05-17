// Modelo plano de método de pago para la build web (sin Isar).
// Espejo de `local_payment_method_io.dart` sin anotaciones Isar.
class LocalPaymentMethod {
  int isarId = 0;

  late String uuid;
  late String name;
  late bool isActive;
  String? provider;
  String? qrImageUrl;
  String? accountDetails;
  late DateTime clientUpdatedAt;

  Map<String, dynamic> toJson() => {
        'id': uuid,
        'name': name,
        'is_active': isActive,
        'provider': provider,
        'qr_image_url': qrImageUrl,
        'account_details': accountDetails,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalPaymentMethod fromJson(Map<String, dynamic> json) {
    return LocalPaymentMethod()
      ..uuid = (json['id'] as String?) ?? ''
      ..name = (json['name'] as String?) ?? ''
      ..isActive = (json['is_active'] as bool?) ?? true
      ..provider = json['provider'] as String?
      ..qrImageUrl = json['qr_image_url'] as String?
      ..accountDetails = json['account_details'] as String?
      ..clientUpdatedAt = DateTime.now();
  }
}
