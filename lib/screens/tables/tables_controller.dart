import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/product.dart';
import '../../models/cart_item.dart';

class TableTab {
  final int tableNumber;
  List<CartItem> items;
  DateTime openedAt;

  TableTab({
    required this.tableNumber,
    List<CartItem>? items,
    DateTime? openedAt,
  })  : items = items ?? [],
        openedAt = openedAt ?? DateTime.now();

  double get total => items.fold(0.0, (sum, i) => sum + i.subtotal);

  bool get isOpen => items.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'table_number': tableNumber,
        'items': items.map((i) => i.toJson()).toList(),
        'opened_at': openedAt.toIso8601String(),
      };

  factory TableTab.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return TableTab(
      tableNumber: json['table_number'] as int,
      items: rawItems
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      openedAt: json['opened_at'] != null
          ? DateTime.parse(json['opened_at'] as String)
          : DateTime.now(),
    );
  }
}

class TablesController extends ChangeNotifier {
  static const String _storageKey = 'vendia_tables';
  static const int _defaultTableCount = 10;

  List<TableTab> _tables = [];
  int _tableCount = _defaultTableCount;

  List<TableTab> get tables => _tables;
  int get tableCount => _tableCount;

  TablesController() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _tableCount = prefs.getInt('vendia_table_count') ?? _defaultTableCount;
    _tables = List.generate(_tableCount, (i) => TableTab(tableNumber: i + 1));

    final saved = prefs.getString(_storageKey);
    if (saved != null && saved.isNotEmpty) {
      try {
        final list = jsonDecode(saved) as List;
        for (final json in list) {
          final tab = TableTab.fromJson(json as Map<String, dynamic>);
          if (tab.tableNumber > 0 && tab.tableNumber <= _tableCount) {
            _tables[tab.tableNumber - 1] = tab;
          }
        }
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final openTabs = _tables.where((t) => t.isOpen).toList();
    await prefs.setString(
      _storageKey,
      jsonEncode(openTabs.map((t) => t.toJson()).toList()),
    );
  }

  TableTab getTable(int number) => _tables[number - 1];

  void openTable(int number) {
    if (_tables[number - 1].items.isEmpty) {
      _tables[number - 1] = TableTab(tableNumber: number);
    }
    notifyListeners();
  }

  void addItemToTable(int number, Product product) {
    final tab = _tables[number - 1];
    final existing =
        tab.items.where((i) => i.product.id == product.id).firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      tab.items.add(CartItem(product: product));
    }
    notifyListeners();
    _persist();
  }

  void incrementItem(int tableNumber, Product product) {
    final tab = _tables[tableNumber - 1];
    final item = tab.items.where((i) => i.product.id == product.id).firstOrNull;
    if (item != null) {
      item.quantity++;
      notifyListeners();
      _persist();
    }
  }

  void decrementItem(int tableNumber, Product product) {
    final tab = _tables[tableNumber - 1];
    final idx = tab.items.indexWhere((i) => i.product.id == product.id);
    if (idx == -1) return;
    if (tab.items[idx].quantity <= 1) {
      tab.items.removeAt(idx);
    } else {
      tab.items[idx].quantity--;
    }
    notifyListeners();
    _persist();
  }

  void closeTable(int number) {
    _tables[number - 1] = TableTab(tableNumber: number);
    notifyListeners();
    _persist();
  }

  String formattedTotal(int number) {
    final total = _tables[number - 1].total;
    final int cents = total.round();
    if (cents == 0) return '\$0';
    final String s = cents.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }
}
