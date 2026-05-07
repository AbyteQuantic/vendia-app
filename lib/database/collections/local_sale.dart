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
  /// Set when the sale was appended to an existing open fiado at checkout
  /// (either via the "Agregar a cuenta existente" picker or via the fresh
  /// handshake flow). Sent to the backend so the Sale row gets linked to
  /// the CreditAccount and the customer statement can show itemized
  /// detail. Persisted so retries from SalesSyncService.pushToServer
  /// don't lose the link when the first sync fails.
  String? creditAccountId;

  /// Sale origin: 'counter' (default), 'mesa', 'fiado'. Used by the
  /// sales history to label rows like "Mesa 4" instead of always
  /// "Venta Mostrador".
  late String saleOrigin;

  /// Mesa label when saleOrigin == 'mesa'. Null otherwise.
  String? tableLabel;

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
        'credit_account_id': creditAccountId,
        'sale_origin': saleOrigin,
        'table_label': tableLabel,
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
      ..creditAccountId = json['credit_account_id'] as String?
      ..saleOrigin = json['sale_origin'] as String? ?? 'counter'
      ..tableLabel = json['table_label'] as String?
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

  /// IVA rate applied to this line at the moment the sale closed.
  /// Null when the merchant had VAT disabled. Once written, NEVER
  /// mutated — preserves the historical math even if the merchant
  /// toggles VAT later.
  double? taxRate;

  /// Frozen monetary value of the IVA charged on this line. Computed
  /// at sale-close time using taxRate + isTaxInclusive + unitPrice
  /// + quantity. Null when taxRate is null.
  double? taxAmount;

  /// Snapshot of the tenant's pricing convention at sale time.
  /// true: unitPrice already includes the IVA (the customer paid
  /// exactly unitPrice * quantity); the taxAmount is extracted from
  /// inside that figure.
  /// false: IVA was added on top; the customer paid
  /// unitPrice * quantity + taxAmount.
  bool? isTaxInclusive;

  double get subtotal => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'product_uuid': productUuid,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'is_container_charge': isContainerCharge,
        'tax_rate': taxRate,
        'tax_amount': taxAmount,
        'is_tax_inclusive': isTaxInclusive,
      };

  static SaleItemEmbed fromJson(Map<String, dynamic> json) {
    return SaleItemEmbed()
      ..productUuid = json['product_uuid'] as String? ?? ''
      ..productName =
          json['product_name'] as String? ?? json['name'] as String? ?? ''
      ..quantity = json['quantity'] as int? ?? 1
      ..unitPrice =
          (json['unit_price'] as num? ?? json['price'] as num? ?? 0).toDouble()
      ..isContainerCharge = json['is_container_charge'] as bool? ?? false
      ..taxRate = (json['tax_rate'] as num?)?.toDouble()
      ..taxAmount = (json['tax_amount'] as num?)?.toDouble()
      ..isTaxInclusive = json['is_tax_inclusive'] as bool?;
  }
}
