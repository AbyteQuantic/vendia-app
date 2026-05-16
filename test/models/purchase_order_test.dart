// Spec: specs/002-ordenes-compra/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/purchase_order.dart';

/// Tests del modelo PurchaseOrder + PurchaseOrderItem — de/serialización
/// y reglas derivadas. Cubre AC-01 (ítems con cantidad/costo y total),
/// AC-02/AC-06 (estados del ciclo de vida) del lado del cliente.
///
/// Lección de F1 (BUG-5/6): el backend embebe `BaseModel`, cuya llave
/// primaria UUID se serializa como `id` (NO `uuid`). El modelo lee `id`.
void main() {
  group('PurchaseOrderItem.fromJson', () {
    test('parsea un ítem de insumo con cantidad y costo', () {
      final item = PurchaseOrderItem.fromJson({
        'id': 'item-1',
        'purchase_order_id': 'po-1',
        'ingredient_id': 'ing-9',
        'name_snapshot': 'Arroz',
        'quantity': 10.0,
        'unit_cost': 3200.0,
      });

      expect(item.uuid, 'item-1');
      expect(item.ingredientId, 'ing-9');
      expect(item.productId, isNull);
      expect(item.nameSnapshot, 'Arroz');
      expect(item.quantity, 10.0);
      expect(item.unitCost, 3200.0);
    });

    test('parsea un ítem de producto', () {
      final item = PurchaseOrderItem.fromJson({
        'id': 'item-2',
        'product_id': 'prod-7',
        'name_snapshot': 'Gaseosa',
        'quantity': 24,
        'unit_cost': 1800,
      });

      expect(item.productId, 'prod-7');
      expect(item.ingredientId, isNull);
      expect(item.quantity, 24.0);
      expect(item.unitCost, 1800.0);
    });

    test('toma el identificador de la llave `id` del backend (BUG-5)', () {
      final item = PurchaseOrderItem.fromJson({
        'id': 'id-del-backend',
        'name_snapshot': 'X',
        'quantity': 1,
        'unit_cost': 1,
      });
      expect(item.uuid, 'id-del-backend');
    });

    test('respalda a la llave `uuid` para datos locales viejos', () {
      final item = PurchaseOrderItem.fromJson({
        'uuid': 'uuid-legacy',
        'name_snapshot': 'X',
        'quantity': 1,
        'unit_cost': 1,
      });
      expect(item.uuid, 'uuid-legacy');
    });

    test('lineTotal es cantidad × costo unitario', () {
      final item = PurchaseOrderItem(
        nameSnapshot: 'Arroz',
        ingredientId: 'ing-1',
        quantity: 10,
        unitCost: 3200,
      );
      expect(item.lineTotal, 32000.0);
    });

    test('isValid: válido cuando referencia exactamente insumo XOR producto',
        () {
      final ingItem = PurchaseOrderItem(
        nameSnapshot: 'Arroz', ingredientId: 'ing-1', quantity: 1, unitCost: 1);
      final prodItem = PurchaseOrderItem(
        nameSnapshot: 'Gaseosa', productId: 'p-1', quantity: 1, unitCost: 1);
      expect(ingItem.isValid, isTrue);
      expect(prodItem.isValid, isTrue);
    });

    test('isValid: inválido cuando no referencia ni insumo ni producto', () {
      final orphan = PurchaseOrderItem(
        nameSnapshot: 'Huérfano', quantity: 1, unitCost: 1);
      expect(orphan.isValid, isFalse);
    });

    test('isValid: inválido cuando referencia insumo Y producto a la vez', () {
      final both = PurchaseOrderItem(
        nameSnapshot: 'Ambos',
        ingredientId: 'ing-1',
        productId: 'p-1',
        quantity: 1,
        unitCost: 1);
      expect(both.isValid, isFalse);
    });

    test('isValid: inválido cuando cantidad o costo <= 0 (caso borde)', () {
      final zeroQty = PurchaseOrderItem(
        nameSnapshot: 'X', ingredientId: 'ing-1', quantity: 0, unitCost: 5);
      final zeroCost = PurchaseOrderItem(
        nameSnapshot: 'X', ingredientId: 'ing-1', quantity: 5, unitCost: 0);
      expect(zeroQty.isValid, isFalse);
      expect(zeroCost.isValid, isFalse);
    });

    test('toJson omite las FK nulas para no romper el insert (Art. X)', () {
      final ingItem = PurchaseOrderItem(
        nameSnapshot: 'Arroz', ingredientId: 'ing-1', quantity: 2, unitCost: 5);
      final json = ingItem.toJson();

      expect(json['ingredient_id'], 'ing-1');
      expect(json.containsKey('product_id'), isFalse);
      expect(json['quantity'], 2);
      expect(json['unit_cost'], 5);
    });
  });

  group('PurchaseOrder.fromJson', () {
    Map<String, dynamic> sampleJson() => {
          'id': 'po-abc',
          'tenant_id': 'tenant-1',
          'supplier_id': 'sup-1',
          'status': 'borrador',
          'total': 50000.0,
          'notes': 'Pedido del lunes',
          'items': [
            {
              'id': 'it-1',
              'ingredient_id': 'ing-1',
              'name_snapshot': 'Arroz',
              'quantity': 10,
              'unit_cost': 3200,
            },
            {
              'id': 'it-2',
              'product_id': 'prod-1',
              'name_snapshot': 'Gaseosa',
              'quantity': 12,
              'unit_cost': 1500,
            },
          ],
          'created_at': '2026-05-16T10:00:00Z',
          'updated_at': '2026-05-16T10:00:00Z',
        };

    test('parsea una PO completa con ítems desde el contrato (AC-01)', () {
      final po = PurchaseOrder.fromJson(sampleJson());

      expect(po.uuid, 'po-abc');
      expect(po.supplierId, 'sup-1');
      expect(po.status, 'borrador');
      expect(po.total, 50000.0);
      expect(po.notes, 'Pedido del lunes');
      expect(po.items, hasLength(2));
      expect(po.items.first.nameSnapshot, 'Arroz');
      expect(po.items.first.quantity, 10.0);
    });

    test('toma el identificador de la llave `id` del backend (BUG-5)', () {
      final po = PurchaseOrder.fromJson({
        'id': 'id-del-backend',
        'supplier_id': 'sup-1',
        'status': 'enviada',
      });
      expect(po.uuid, 'id-del-backend');
    });

    test('respalda a la llave `uuid` para datos locales viejos', () {
      final po = PurchaseOrder.fromJson({
        'uuid': 'uuid-legacy',
        'supplier_id': 'sup-1',
        'status': 'borrador',
      });
      expect(po.uuid, 'uuid-legacy');
    });

    test('lanza FormatException cuando no hay id ni uuid', () {
      expect(
        () => PurchaseOrder.fromJson({'supplier_id': 'sup-1'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('aplica defaults cuando faltan campos opcionales', () {
      final po = PurchaseOrder.fromJson({
        'id': 'po-x',
        'supplier_id': 'sup-1',
        'status': 'borrador',
      });
      expect(po.total, 0);
      expect(po.notes, isNull);
      expect(po.items, isEmpty);
      expect(po.sentAt, isNull);
      expect(po.receivedAt, isNull);
    });

    test('parsea las marcas de tiempo de envío y recepción', () {
      final po = PurchaseOrder.fromJson({
        'id': 'po-r',
        'supplier_id': 'sup-1',
        'status': 'recibida',
        'sent_at': '2026-05-16T11:00:00Z',
        'received_at': '2026-05-17T09:00:00Z',
      });
      expect(po.sentAt, isNotNull);
      expect(po.receivedAt, isNotNull);
    });

    test('acepta cantidad y costo como int del backend (num)', () {
      final po = PurchaseOrder.fromJson({
        'id': 'po-n',
        'supplier_id': 'sup-1',
        'status': 'borrador',
        'total': 12000,
        'items': [
          {
            'id': 'it',
            'ingredient_id': 'ing-1',
            'name_snapshot': 'Aceite',
            'quantity': 3,
            'unit_cost': 4000,
          },
        ],
      });
      expect(po.total, 12000.0);
      expect(po.items.first.quantity, 3.0);
      expect(po.items.first.unitCost, 4000.0);
    });
  });

  group('PurchaseOrder.toJson', () {
    test('serializa el cuerpo que el backend espera en POST', () {
      final po = PurchaseOrder(
        uuid: 'po-1',
        supplierId: 'sup-1',
        status: 'borrador',
        notes: 'Urgente',
        items: [
          PurchaseOrderItem(
            nameSnapshot: 'Arroz',
            ingredientId: 'ing-1',
            quantity: 10,
            unitCost: 3200),
        ],
      );
      final json = po.toJson();

      // El contrato POST /api/v1/purchase-orders incluye el `id` que el
      // cliente genera (idempotencia offline — Art. II).
      expect(json['id'], 'po-1');
      expect(json['supplier_id'], 'sup-1');
      expect(json['notes'], 'Urgente');
      expect(json['items'], hasLength(1));
      expect((json['items'] as List).first['ingredient_id'], 'ing-1');
    });

    test('omite notes cuando es nulo (Art. X)', () {
      final po = PurchaseOrder(
        uuid: 'po-2', supplierId: 'sup-1', status: 'borrador');
      expect(po.toJson().containsKey('notes'), isFalse);
    });
  });

  group('PurchaseOrder — reglas derivadas del ciclo de vida', () {
    PurchaseOrder withStatus(String s) =>
        PurchaseOrder(uuid: 'po', supplierId: 'sup-1', status: s);

    test('computedTotal suma los lineTotal de los ítems', () {
      final po = PurchaseOrder(
        uuid: 'po', supplierId: 'sup-1', status: 'borrador',
        items: [
          PurchaseOrderItem(
            nameSnapshot: 'A', ingredientId: 'i1', quantity: 10, unitCost: 3200),
          PurchaseOrderItem(
            nameSnapshot: 'B', productId: 'p1', quantity: 12, unitCost: 1500),
        ],
      );
      expect(po.computedTotal, 32000.0 + 18000.0);
    });

    test('isEditable solo en borrador (plan §4: editar solo en borrador)', () {
      expect(withStatus('borrador').isEditable, isTrue);
      expect(withStatus('enviada').isEditable, isFalse);
      expect(withStatus('recibida').isEditable, isFalse);
      expect(withStatus('cancelada').isEditable, isFalse);
    });

    test('canSend desde borrador con ítems (AC-02)', () {
      final draftWithItems = PurchaseOrder(
        uuid: 'po', supplierId: 'sup-1', status: 'borrador',
        items: [
          PurchaseOrderItem(
            nameSnapshot: 'A', ingredientId: 'i1', quantity: 1, unitCost: 1),
        ],
      );
      expect(draftWithItems.canSend, isTrue);
    });

    test('canSend es falso para una PO sin ítems (caso borde §9)', () {
      expect(withStatus('borrador').canSend, isFalse);
    });

    test('canReceive desde borrador o enviada con ítems (D3, AC-03)', () {
      final draft = PurchaseOrder(
        uuid: 'po', supplierId: 'sup-1', status: 'borrador',
        items: [
          PurchaseOrderItem(
            nameSnapshot: 'A', ingredientId: 'i1', quantity: 1, unitCost: 1),
        ]);
      final sent = draft.copyWith(status: 'enviada');
      expect(draft.canReceive, isTrue);
      expect(sent.canReceive, isTrue);
    });

    test('canReceive es falso para una PO recibida o cancelada (AC-04/AC-06)',
        () {
      final received = PurchaseOrder(
        uuid: 'po', supplierId: 'sup-1', status: 'recibida',
        items: [
          PurchaseOrderItem(
            nameSnapshot: 'A', ingredientId: 'i1', quantity: 1, unitCost: 1),
        ]);
      final canceled = received.copyWith(status: 'cancelada');
      expect(received.canReceive, isFalse);
      expect(canceled.canReceive, isFalse);
    });

    test('canCancel solo desde borrador o enviada (AC-06)', () {
      expect(withStatus('borrador').canCancel, isTrue);
      expect(withStatus('enviada').canCancel, isTrue);
      expect(withStatus('recibida').canCancel, isFalse);
      expect(withStatus('cancelada').canCancel, isFalse);
    });

    test('isTerminal para recibida y cancelada (spec §7)', () {
      expect(withStatus('recibida').isTerminal, isTrue);
      expect(withStatus('cancelada').isTerminal, isTrue);
      expect(withStatus('borrador').isTerminal, isFalse);
      expect(withStatus('enviada').isTerminal, isFalse);
    });

    test('statusLabel devuelve la etiqueta legible en español', () {
      expect(withStatus('borrador').statusLabel, 'Borrador');
      expect(withStatus('enviada').statusLabel, 'Enviada');
      expect(withStatus('recibida').statusLabel, 'Recibida');
      expect(withStatus('cancelada').statusLabel, 'Cancelada');
    });

    test('copyWith devuelve una copia inmutable con el cambio aplicado', () {
      final original = withStatus('borrador');
      final updated = original.copyWith(status: 'enviada');
      expect(updated.status, 'enviada');
      expect(original.status, 'borrador'); // el original no muta (Art. IX)
      expect(updated.uuid, original.uuid);
    });
  });
}
