import 'package:isar/isar.dart';

part 'local_table_tab_io.g.dart';

@collection
class LocalTableTab {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String label;

  String? sessionToken;
  String? orderId;

  late List<LocalTabItem> items;
  late double grossTotal;
  late double abonosTotal;
  late double pendingBalance;
  late String status;
  late DateTime updatedAt;
  late bool synced;

  Map<String, dynamic> toJson() => {
        'label': label,
        'session_token': sessionToken,
        'order_id': orderId,
        'items': items.map((i) => i.toJson()).toList(),
        'gross_total': grossTotal,
        'abonos_total': abonosTotal,
        'pending_balance': pendingBalance,
        'status': status,
        'updated_at': updatedAt.toIso8601String(),
      };
}

@embedded
class LocalTabItem {
  late String productUuid;
  late String productName;
  late int quantity;
  late double unitPrice;
  DateTime? sentAt;

  Map<String, dynamic> toJson() => {
        'product_uuid': productUuid,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'sent_at': sentAt?.toIso8601String(),
      };
}
