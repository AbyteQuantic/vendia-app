// Modelo plano de cliente para la build web (sin Isar).
// Espejo de `local_customer_io.dart` sin anotaciones Isar.
class LocalCustomer {
  int isarId = 0;

  late String uuid;
  late String name;
  late String phone;

  /// Email del cliente — opcional (F032). Espejo del campo de
  /// `local_customer_io.dart`.
  String email = '';

  late double totalCredit;
  late double totalPaid;
  late DateTime createdAt;
  late DateTime clientUpdatedAt;
  int? serverId;

  double get balance => totalCredit - totalPaid;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'phone': phone,
        'email': email,
        'total_credit': totalCredit,
        'total_paid': totalPaid,
        'created_at': createdAt.toIso8601String(),
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalCustomer fromJson(Map<String, dynamic> json) {
    return LocalCustomer()
      ..uuid = json['uuid'] as String? ?? ''
      ..name = json['name'] as String
      ..phone = json['phone'] as String? ?? ''
      ..email = json['email'] as String? ?? ''
      ..totalCredit = (json['total_credit'] as num? ?? 0).toDouble()
      ..totalPaid = (json['total_paid'] as num? ?? 0).toDouble()
      ..createdAt = json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now()
      ..clientUpdatedAt = json['client_updated_at'] != null
          ? DateTime.parse(json['client_updated_at'] as String)
          : DateTime.now()
      ..serverId = json['id'] as int?;
  }
}
