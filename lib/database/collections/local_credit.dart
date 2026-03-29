import 'package:isar/isar.dart';

part 'local_credit.g.dart';

@collection
class LocalCredit {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  @Index()
  late String customerUuid;

  late String saleUuid;
  late double totalAmount;
  late double paidAmount;
  late String status;
  late List<CreditPaymentEmbed> payments;
  late DateTime createdAt;
  late DateTime clientUpdatedAt;

  double get balance => totalAmount - paidAmount;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'customer_uuid': customerUuid,
        'sale_uuid': saleUuid,
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'status': status,
        'payments': payments.map((p) => p.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  static LocalCredit fromJson(Map<String, dynamic> json) {
    final rawPayments = json['payments'] as List? ?? [];
    return LocalCredit()
      ..uuid = json['uuid'] as String? ?? ''
      ..customerUuid = json['customer_uuid'] as String? ?? ''
      ..saleUuid = json['sale_uuid'] as String? ?? ''
      ..totalAmount = (json['total_amount'] as num? ?? 0).toDouble()
      ..paidAmount = (json['paid_amount'] as num? ?? 0).toDouble()
      ..status = json['status'] as String? ?? 'pending'
      ..payments = rawPayments
          .map((e) => CreditPaymentEmbed.fromJson(e as Map<String, dynamic>))
          .toList()
      ..createdAt = json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now()
      ..clientUpdatedAt = json['client_updated_at'] != null
          ? DateTime.parse(json['client_updated_at'] as String)
          : DateTime.now();
  }
}

@embedded
class CreditPaymentEmbed {
  late String uuid;
  late double amount;
  late DateTime paidAt;
  late String note;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'amount': amount,
        'paid_at': paidAt.toIso8601String(),
        'note': note,
      };

  static CreditPaymentEmbed fromJson(Map<String, dynamic> json) {
    return CreditPaymentEmbed()
      ..uuid = json['uuid'] as String? ?? ''
      ..amount = (json['amount'] as num? ?? 0).toDouble()
      ..paidAt = json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : DateTime.now()
      ..note = json['note'] as String? ?? '';
  }
}
