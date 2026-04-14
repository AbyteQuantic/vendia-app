import 'package:isar/isar.dart';

part 'local_sale.g.dart';

@collection
class LocalSale {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late double total;
  late String paymentMethod;
  String? customerUuid;
  String? employeeName;
  late bool isCreditSale;
  late List<SaleItemEmbed> items;
  late DateTime createdAt;
  late bool synced;
  int? serverId;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'total': total,
        'payment_method': paymentMethod,
        'customer_uuid': customerUuid,
        'employee_name': employeeName,
        'is_credit_sale': isCreditSale,
        'items': items.map((i) => i.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
      };

  static LocalSale fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return LocalSale()
      ..uuid = json['uuid'] as String? ?? ''
      ..total = (json['total'] as num).toDouble()
      ..paymentMethod = json['payment_method'] as String? ?? 'cash'
      ..customerUuid = json['customer_uuid'] as String?
      ..employeeName = json['employee_name'] as String?
      ..isCreditSale = json['is_credit_sale'] as bool? ?? false
      ..items = rawItems
          .map((e) => SaleItemEmbed.fromJson(e as Map<String, dynamic>))
          .toList()
      ..createdAt = json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now()
      ..synced = json['synced'] as bool? ?? false
      ..serverId = json['server_id'] as int?;
  }
}

@embedded
class SaleItemEmbed {
  late String productUuid;
  late String productName;
  late int quantity;
  late double unitPrice;
  late bool isContainerCharge;

  double get subtotal => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'product_uuid': productUuid,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'is_container_charge': isContainerCharge,
      };

  static SaleItemEmbed fromJson(Map<String, dynamic> json) {
    return SaleItemEmbed()
      ..productUuid = json['product_uuid'] as String? ?? ''
      ..productName =
          json['product_name'] as String? ?? json['name'] as String? ?? ''
      ..quantity = json['quantity'] as int? ?? 1
      ..unitPrice =
          (json['unit_price'] as num? ?? json['price'] as num? ?? 0).toDouble()
      ..isContainerCharge = json['is_container_charge'] as bool? ?? false;
  }
}
