import 'package:isar/isar.dart';

part 'local_customer.g.dart';

@collection
class LocalCustomer {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late String name;
  late String phone;
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
