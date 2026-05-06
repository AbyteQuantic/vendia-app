import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sale history customer label', () {
    String customerLabel(Map<String, dynamic> sale) {
      final name = (sale['customer_name_snapshot'] as String?) ?? '';
      if (name.isNotEmpty) return name;
      final origin = (sale['sale_origin'] as String?) ?? 'counter';
      final tableLabel = (sale['table_label'] as String?) ?? '';
      if (origin == 'mesa' && tableLabel.isNotEmpty) return tableLabel;
      final method = (sale['payment_method'] as String?) ?? '';
      if (method == 'credit' || origin == 'fiado') return 'Fiado';
      return 'Venta Mostrador';
    }

    test('mesa origin → returns table label', () {
      expect(customerLabel({
        'sale_origin': 'mesa',
        'table_label': 'Mesa 4',
        'payment_method': 'multi',
      }), 'Mesa 4');
    });

    test('mesa origin without label falls back to Venta Mostrador', () {
      expect(customerLabel({
        'sale_origin': 'mesa',
        'payment_method': 'multi',
      }), 'Venta Mostrador');
    });

    test('counter origin (default) shows Venta Mostrador', () {
      expect(customerLabel({
        'sale_origin': 'counter',
        'payment_method': 'cash',
      }), 'Venta Mostrador');
    });

    test('credit method always shows Fiado', () {
      expect(customerLabel({
        'sale_origin': 'counter',
        'payment_method': 'credit',
      }), 'Fiado');
    });

    test('fiado origin (no method) shows Fiado', () {
      expect(customerLabel({
        'sale_origin': 'fiado',
        'payment_method': 'cash',
      }), 'Fiado');
    });

    test('customer name overrides origin', () {
      expect(customerLabel({
        'customer_name_snapshot': 'Don Carlos',
        'sale_origin': 'mesa',
        'table_label': 'Mesa 7',
      }), 'Don Carlos');
    });
  });

  group('Method label mapping', () {
    String methodLabel(String m) => switch (m) {
      'cash' => 'Efectivo',
      'transfer' => 'Transferencia',
      'card' => 'Tarjeta',
      'nequi' => 'Nequi',
      'daviplata' => 'Daviplata',
      'credit' => 'Fiado',
      'multi' => 'Pago Mixto',
      _ => m.isEmpty ? 'Otro' : m,
    };

    test('multi maps to Pago Mixto', () {
      expect(methodLabel('multi'), 'Pago Mixto');
    });

    test('cash/transfer/card/nequi/daviplata preserved', () {
      expect(methodLabel('cash'), 'Efectivo');
      expect(methodLabel('transfer'), 'Transferencia');
      expect(methodLabel('card'), 'Tarjeta');
      expect(methodLabel('nequi'), 'Nequi');
      expect(methodLabel('daviplata'), 'Daviplata');
    });

    test('empty string maps to Otro', () {
      expect(methodLabel(''), 'Otro');
    });

    test('unknown string returns itself (forward-compatible)', () {
      expect(methodLabel('unknown'), 'unknown');
    });

    test('credit maps to Fiado', () {
      expect(methodLabel('credit'), 'Fiado');
    });
  });
}
