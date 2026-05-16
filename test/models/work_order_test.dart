// Spec: specs/003-trabajos-muebles/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/work_order.dart';

/// Tests del modelo WorkOrder + WorkOrderItem + WorkOrderPayment —
/// de/serialización y reglas derivadas. Cubre AC-01 (total = Σ ítems),
/// AC-02 (abonado/saldo), AC-05 (transiciones) y AC-07 (ítems congelados)
/// del lado del cliente.
///
/// Lección de F1 (BUG-5/6): el backend Go embebe `BaseModel`, cuya llave
/// primaria UUID se serializa como `id` (NO `uuid`). El modelo lee `id`.
void main() {
  group('WorkOrderItem.fromJson', () {
    test('parsea un ítem de material que referencia un insumo', () {
      final item = WorkOrderItem.fromJson({
        'id': 'item-1',
        'work_order_id': 'wo-1',
        'kind': 'material',
        'ingredient_id': 'ing-9',
        'description': 'Madera',
        'quantity': 2.0,
        'unit_price': 20000.0,
      });

      expect(item.uuid, 'item-1');
      expect(item.kind, WorkOrderItem.kindMaterial);
      expect(item.ingredientId, 'ing-9');
      expect(item.productId, isNull);
      expect(item.description, 'Madera');
      expect(item.quantity, 2.0);
      expect(item.unitPrice, 20000.0);
    });

    test('parsea un ítem de material que referencia un producto', () {
      final item = WorkOrderItem.fromJson({
        'id': 'item-2',
        'kind': 'material',
        'product_id': 'prod-7',
        'description': 'Bisagra',
        'quantity': 4,
        'unit_price': 1500,
      });

      expect(item.productId, 'prod-7');
      expect(item.ingredientId, isNull);
      expect(item.isMaterial, isTrue);
      expect(item.quantity, 4.0);
      expect(item.unitPrice, 1500.0);
    });

    test('parsea un ítem de mano de obra sin referencia de inventario', () {
      final item = WorkOrderItem.fromJson({
        'id': 'item-3',
        'kind': 'mano_obra',
        'description': 'Armado y lijado',
        'quantity': 1,
        'unit_price': 50000,
      });

      expect(item.kind, WorkOrderItem.kindLabor);
      expect(item.isLabor, isTrue);
      expect(item.ingredientId, isNull);
      expect(item.productId, isNull);
    });

    test('toma el identificador de la llave `id` del backend (BUG-5)', () {
      final item = WorkOrderItem.fromJson({
        'id': 'id-del-backend',
        'kind': 'mano_obra',
        'description': 'X',
        'quantity': 1,
        'unit_price': 1,
      });
      expect(item.uuid, 'id-del-backend');
    });

    test('respalda a la llave `uuid` para datos locales viejos', () {
      final item = WorkOrderItem.fromJson({
        'uuid': 'uuid-legacy',
        'kind': 'mano_obra',
        'description': 'X',
        'quantity': 1,
        'unit_price': 1,
      });
      expect(item.uuid, 'uuid-legacy');
    });

    test('lineTotal es cantidad × precio unitario (AC-01)', () {
      final item = WorkOrderItem(
        kind: WorkOrderItem.kindMaterial,
        ingredientId: 'ing-1',
        description: 'Madera',
        quantity: 2,
        unitPrice: 20000,
      );
      expect(item.lineTotal, 40000.0);
    });

    test('isValid: material válido cuando referencia insumo XOR producto', () {
      final ingItem = WorkOrderItem(
        kind: WorkOrderItem.kindMaterial,
        ingredientId: 'ing-1',
        description: 'Madera',
        quantity: 1,
        unitPrice: 1,
      );
      final prodItem = WorkOrderItem(
        kind: WorkOrderItem.kindMaterial,
        productId: 'p-1',
        description: 'Bisagra',
        quantity: 1,
        unitPrice: 1,
      );
      expect(ingItem.isValid, isTrue);
      expect(prodItem.isValid, isTrue);
    });

    test('isValid: material inválido sin referencia de inventario', () {
      final orphan = WorkOrderItem(
        kind: WorkOrderItem.kindMaterial,
        description: 'Huérfano',
        quantity: 1,
        unitPrice: 1,
      );
      expect(orphan.isValid, isFalse);
    });

    test('isValid: material inválido si referencia insumo Y producto', () {
      final both = WorkOrderItem(
        kind: WorkOrderItem.kindMaterial,
        ingredientId: 'ing-1',
        productId: 'p-1',
        description: 'Ambos',
        quantity: 1,
        unitPrice: 1,
      );
      expect(both.isValid, isFalse);
    });

    test('isValid: mano de obra válida sin referencia de inventario', () {
      final labor = WorkOrderItem(
        kind: WorkOrderItem.kindLabor,
        description: 'Pintura',
        quantity: 1,
        unitPrice: 50000,
      );
      expect(labor.isValid, isTrue);
    });

    test('isValid: mano de obra inválida si referencia inventario', () {
      final labor = WorkOrderItem(
        kind: WorkOrderItem.kindLabor,
        ingredientId: 'ing-1',
        description: 'Pintura',
        quantity: 1,
        unitPrice: 50000,
      );
      expect(labor.isValid, isFalse);
    });

    test('isValid: inválido cuando cantidad o precio <= 0', () {
      final zeroQty = WorkOrderItem(
        kind: WorkOrderItem.kindLabor,
        description: 'X',
        quantity: 0,
        unitPrice: 5,
      );
      final zeroPrice = WorkOrderItem(
        kind: WorkOrderItem.kindLabor,
        description: 'X',
        quantity: 1,
        unitPrice: 0,
      );
      expect(zeroQty.isValid, isFalse);
      expect(zeroPrice.isValid, isFalse);
    });

    test('toJson omite las FK nulas para no romper el insert (Art. X)', () {
      final ingItem = WorkOrderItem(
        kind: WorkOrderItem.kindMaterial,
        ingredientId: 'ing-1',
        description: 'Madera',
        quantity: 2,
        unitPrice: 20000,
      );
      final json = ingItem.toJson();

      expect(json['kind'], 'material');
      expect(json['ingredient_id'], 'ing-1');
      expect(json.containsKey('product_id'), isFalse);
      expect(json['description'], 'Madera');
      expect(json['quantity'], 2);
      expect(json['unit_price'], 20000);
    });

    test('toJson de mano de obra no envía referencias de inventario', () {
      final labor = WorkOrderItem(
        kind: WorkOrderItem.kindLabor,
        description: 'Armado',
        quantity: 1,
        unitPrice: 50000,
      );
      final json = labor.toJson();
      expect(json['kind'], 'mano_obra');
      expect(json.containsKey('ingredient_id'), isFalse);
      expect(json.containsKey('product_id'), isFalse);
    });

    test('kindLabel devuelve la etiqueta legible en español', () {
      expect(
        WorkOrderItem(
          kind: WorkOrderItem.kindMaterial,
          ingredientId: 'i',
          description: 'X',
          quantity: 1,
          unitPrice: 1,
        ).kindLabel,
        'Material',
      );
      expect(
        WorkOrderItem(
          kind: WorkOrderItem.kindLabor,
          description: 'X',
          quantity: 1,
          unitPrice: 1,
        ).kindLabel,
        'Mano de obra',
      );
    });

    test('copyWith devuelve una copia inmutable con el cambio aplicado', () {
      final original = WorkOrderItem(
        kind: WorkOrderItem.kindLabor,
        description: 'X',
        quantity: 1,
        unitPrice: 1000,
      );
      final updated = original.copyWith(unitPrice: 2000);
      expect(updated.unitPrice, 2000);
      expect(original.unitPrice, 1000); // el original no muta (Art. IX)
    });
  });

  group('WorkOrderPayment.fromJson', () {
    test('parsea un anticipo del cliente', () {
      final payment = WorkOrderPayment.fromJson({
        'id': 'pay-1',
        'work_order_id': 'wo-1',
        'amount': 40000.0,
        'method': 'efectivo',
        'paid_at': '2026-05-16T10:00:00Z',
      });
      expect(payment.uuid, 'pay-1');
      expect(payment.amount, 40000.0);
      expect(payment.method, 'efectivo');
      expect(payment.paidAt, isNotNull);
    });

    test('toma el identificador de la llave `id` del backend (BUG-5)', () {
      final payment = WorkOrderPayment.fromJson({
        'id': 'id-del-backend',
        'amount': 1000,
        'method': 'efectivo',
      });
      expect(payment.uuid, 'id-del-backend');
    });

    test('acepta amount como int del backend (num)', () {
      final payment = WorkOrderPayment.fromJson({
        'id': 'pay-n',
        'amount': 25000,
        'method': 'nequi',
      });
      expect(payment.amount, 25000.0);
    });

    test('toJson serializa el cuerpo que el backend espera', () {
      final payment = WorkOrderPayment(
        uuid: 'pay-1',
        amount: 40000,
        method: 'efectivo',
      );
      final json = payment.toJson();
      expect(json['amount'], 40000);
      expect(json['method'], 'efectivo');
    });
  });

  group('WorkOrder.fromJson', () {
    Map<String, dynamic> sampleJson() => {
          'id': 'wo-abc',
          'tenant_id': 'tenant-1',
          'customer_id': 'cust-1',
          'type': 'fabricacion',
          'status': 'cotizacion',
          'description': 'Mesa de comedor a la medida',
          'total': 90000.0,
          'abonado': 40000.0,
          'saldo': 50000.0,
          'notes': 'Madera de pino',
          'items': [
            {
              'id': 'it-1',
              'kind': 'material',
              'ingredient_id': 'ing-1',
              'description': 'Madera',
              'quantity': 2,
              'unit_price': 20000,
            },
            {
              'id': 'it-2',
              'kind': 'mano_obra',
              'description': 'Armado',
              'quantity': 1,
              'unit_price': 50000,
            },
          ],
          'payments': [
            {
              'id': 'pay-1',
              'amount': 40000,
              'method': 'efectivo',
              'paid_at': '2026-05-16T10:00:00Z',
            },
          ],
          'created_at': '2026-05-16T09:00:00Z',
          'updated_at': '2026-05-16T09:00:00Z',
        };

    test('parsea un trabajo completo con ítems y pagos (AC-01, AC-02)', () {
      final wo = WorkOrder.fromJson(sampleJson());

      expect(wo.uuid, 'wo-abc');
      expect(wo.customerId, 'cust-1');
      expect(wo.type, WorkOrder.typeManufacture);
      expect(wo.status, WorkOrder.statusQuote);
      expect(wo.description, 'Mesa de comedor a la medida');
      expect(wo.total, 90000.0);
      expect(wo.paid, 40000.0);
      expect(wo.balance, 50000.0);
      expect(wo.notes, 'Madera de pino');
      expect(wo.items, hasLength(2));
      expect(wo.payments, hasLength(1));
    });

    test('toma el identificador de la llave `id` del backend (BUG-5)', () {
      final wo = WorkOrder.fromJson({
        'id': 'id-del-backend',
        'customer_id': 'c-1',
        'type': 'reparacion',
        'status': 'cotizacion',
        'description': 'Arreglo de silla',
      });
      expect(wo.uuid, 'id-del-backend');
    });

    test('respalda a la llave `uuid` para datos locales viejos', () {
      final wo = WorkOrder.fromJson({
        'uuid': 'uuid-legacy',
        'customer_id': 'c-1',
        'type': 'fabricacion',
        'status': 'cotizacion',
        'description': 'X',
      });
      expect(wo.uuid, 'uuid-legacy');
    });

    test('lanza FormatException cuando no hay id ni uuid', () {
      expect(
        () => WorkOrder.fromJson({'customer_id': 'c-1'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('aplica defaults cuando faltan campos opcionales', () {
      final wo = WorkOrder.fromJson({
        'id': 'wo-x',
        'customer_id': 'c-1',
        'type': 'fabricacion',
        'status': 'cotizacion',
        'description': 'X',
      });
      expect(wo.total, 0);
      expect(wo.paid, 0);
      expect(wo.balance, 0);
      expect(wo.notes, isNull);
      expect(wo.items, isEmpty);
      expect(wo.payments, isEmpty);
    });

    test('parsea las marcas de tiempo del ciclo de vida', () {
      final wo = WorkOrder.fromJson({
        'id': 'wo-r',
        'customer_id': 'c-1',
        'type': 'reparacion',
        'status': 'entregada',
        'description': 'X',
        'approved_at': '2026-05-16T11:00:00Z',
        'completed_at': '2026-05-17T09:00:00Z',
        'delivered_at': '2026-05-18T09:00:00Z',
      });
      expect(wo.approvedAt, isNotNull);
      expect(wo.completedAt, isNotNull);
      expect(wo.deliveredAt, isNotNull);
    });

    test('calcula saldo localmente cuando el backend no lo envía', () {
      // Mientras se arma offline el backend aún no calculó abonado/saldo;
      // el cliente los deriva de total y la suma de pagos.
      final wo = WorkOrder.fromJson({
        'id': 'wo-l',
        'customer_id': 'c-1',
        'type': 'fabricacion',
        'status': 'aprobada',
        'description': 'X',
        'total': 90000,
        'payments': [
          {'id': 'p1', 'amount': 30000, 'method': 'efectivo'},
        ],
      });
      expect(wo.paid, 30000.0);
      expect(wo.balance, 60000.0);
    });
  });

  group('WorkOrder.toJson', () {
    test('serializa el cuerpo que el backend espera en POST', () {
      final wo = WorkOrder(
        uuid: 'wo-1',
        customerId: 'cust-1',
        type: WorkOrder.typeManufacture,
        status: WorkOrder.statusQuote,
        description: 'Mesa de comedor',
        notes: 'Pino',
        items: [
          WorkOrderItem(
            kind: WorkOrderItem.kindMaterial,
            ingredientId: 'ing-1',
            description: 'Madera',
            quantity: 2,
            unitPrice: 20000,
          ),
        ],
      );
      final json = wo.toJson();

      // El contrato POST /api/v1/work-orders incluye el `id` que el
      // cliente genera (idempotencia offline — Art. II).
      expect(json['id'], 'wo-1');
      expect(json['customer_id'], 'cust-1');
      expect(json['type'], 'fabricacion');
      expect(json['description'], 'Mesa de comedor');
      expect(json['notes'], 'Pino');
      expect(json['items'], hasLength(1));
      expect((json['items'] as List).first['ingredient_id'], 'ing-1');
    });

    test('omite notes cuando es nulo (Art. X)', () {
      final wo = WorkOrder(
        uuid: 'wo-2',
        customerId: 'c-1',
        type: WorkOrder.typeRepair,
        status: WorkOrder.statusQuote,
        description: 'X',
      );
      expect(wo.toJson().containsKey('notes'), isFalse);
    });
  });

  group('WorkOrder — reglas derivadas del ciclo de vida', () {
    WorkOrder withStatus(String s, {List<WorkOrderItem>? items}) => WorkOrder(
          uuid: 'wo',
          customerId: 'c-1',
          type: WorkOrder.typeManufacture,
          status: s,
          description: 'X',
          items: items ?? const [],
        );

    WorkOrderItem labor() => WorkOrderItem(
          kind: WorkOrderItem.kindLabor,
          description: 'Armado',
          quantity: 1,
          unitPrice: 50000,
        );

    test('computedTotal suma los lineTotal de los ítems (AC-01)', () {
      final wo = withStatus('cotizacion', items: [
        WorkOrderItem(
          kind: WorkOrderItem.kindMaterial,
          ingredientId: 'i1',
          description: 'Madera',
          quantity: 2,
          unitPrice: 20000,
        ),
        labor(),
      ]);
      expect(wo.computedTotal, 40000.0 + 50000.0);
    });

    test('isEditable solo en cotizacion o aprobada (AC-07)', () {
      expect(withStatus('cotizacion').isEditable, isTrue);
      expect(withStatus('aprobada').isEditable, isTrue);
      expect(withStatus('en_proceso').isEditable, isFalse);
      expect(withStatus('terminada').isEditable, isFalse);
      expect(withStatus('entregada').isEditable, isFalse);
      expect(withStatus('cancelada').isEditable, isFalse);
    });

    test('isTerminal para entregada y cancelada (spec §7)', () {
      expect(withStatus('entregada').isTerminal, isTrue);
      expect(withStatus('cancelada').isTerminal, isTrue);
      expect(withStatus('cotizacion').isTerminal, isFalse);
      expect(withStatus('terminada').isTerminal, isFalse);
    });

    test('canShare solo en cotizacion (AC-06)', () {
      expect(withStatus('cotizacion').canShare, isTrue);
      expect(withStatus('aprobada').canShare, isFalse);
      expect(withStatus('terminada').canShare, isFalse);
    });

    test('nextStatus avanza el ciclo de vida lineal', () {
      expect(withStatus('cotizacion').nextStatus, 'aprobada');
      expect(withStatus('aprobada').nextStatus, 'en_proceso');
      expect(withStatus('en_proceso').nextStatus, 'terminada');
      expect(withStatus('terminada').nextStatus, 'entregada');
    });

    test('nextStatus es null en estados terminales', () {
      expect(withStatus('entregada').nextStatus, isNull);
      expect(withStatus('cancelada').nextStatus, isNull);
    });

    test('canAdvance es falso para aprobar un trabajo sin ítems (caso borde)',
        () {
      // Un trabajo en cotizacion sin ítems no puede pasar a aprobada.
      expect(withStatus('cotizacion').canAdvance, isFalse);
      expect(
        withStatus('cotizacion', items: [labor()]).canAdvance,
        isTrue,
      );
    });

    test('canAdvance es falso en estados terminales', () {
      expect(withStatus('entregada', items: [labor()]).canAdvance, isFalse);
      expect(withStatus('cancelada', items: [labor()]).canAdvance, isFalse);
    });

    test('canCancel salvo en estados terminales', () {
      expect(withStatus('cotizacion').canCancel, isTrue);
      expect(withStatus('aprobada').canCancel, isTrue);
      expect(withStatus('en_proceso').canCancel, isTrue);
      expect(withStatus('terminada').canCancel, isTrue);
      expect(withStatus('entregada').canCancel, isFalse);
      expect(withStatus('cancelada').canCancel, isFalse);
    });

    test('isValidTransition acepta solo transiciones del ciclo (AC-05)', () {
      expect(
        WorkOrder.isValidTransition('cotizacion', 'aprobada'),
        isTrue,
      );
      expect(
        WorkOrder.isValidTransition('aprobada', 'en_proceso'),
        isTrue,
      );
      // Saltarse pasos o ir hacia atrás se rechaza.
      expect(
        WorkOrder.isValidTransition('cotizacion', 'entregada'),
        isFalse,
      );
      expect(
        WorkOrder.isValidTransition('terminada', 'cotizacion'),
        isFalse,
      );
      // Cancelar es válido desde cualquier estado no terminal.
      expect(
        WorkOrder.isValidTransition('en_proceso', 'cancelada'),
        isTrue,
      );
      expect(
        WorkOrder.isValidTransition('entregada', 'cancelada'),
        isFalse,
      );
    });

    test('statusLabel y typeLabel devuelven texto legible en español', () {
      expect(withStatus('cotizacion').statusLabel, 'Cotización');
      expect(withStatus('aprobada').statusLabel, 'Aprobada');
      expect(withStatus('en_proceso').statusLabel, 'En proceso');
      expect(withStatus('terminada').statusLabel, 'Terminada');
      expect(withStatus('entregada').statusLabel, 'Entregada');
      expect(withStatus('cancelada').statusLabel, 'Cancelada');
      expect(withStatus('cotizacion').typeLabel, 'Fabricación');
      expect(
        WorkOrder(
          uuid: 'w',
          customerId: 'c',
          type: WorkOrder.typeRepair,
          status: 'cotizacion',
          description: 'X',
        ).typeLabel,
        'Reparación',
      );
    });

    test('copyWith devuelve una copia inmutable con el cambio aplicado', () {
      final original = withStatus('cotizacion');
      final updated = original.copyWith(status: 'aprobada');
      expect(updated.status, 'aprobada');
      expect(original.status, 'cotizacion'); // el original no muta (Art. IX)
      expect(updated.uuid, original.uuid);
    });
  });
}
