// Spec: specs/092-offline-web/spec.md
//
// La persistencia offline en web (localStorage) serializa PendingOperation con
// toJson/fromJson. Este roundtrip pin protege que una venta/operación encolada
// sobreviva a un refresh sin perder campos.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/pending_operation.dart';

void main() {
  test('PendingOperation toJson→fromJson conserva todos los campos', () {
    final now = DateTime.parse('2026-06-28T10:30:00.000');
    final op = PendingOperation()
      ..id = 7
      ..uuid = 'op-uuid-123'
      ..entity = 'sale'
      ..action = 'create'
      ..jsonData = '{"total":1500,"items":2}'
      ..clientUpdatedAt = now
      ..retryCount = 2
      ..createdAt = now
      ..tenantId = 'tenant-abc';

    final back = PendingOperation.fromJson(op.toJson());

    expect(back.id, 7);
    expect(back.uuid, 'op-uuid-123');
    expect(back.entity, 'sale');
    expect(back.action, 'create');
    expect(back.jsonData, '{"total":1500,"items":2}');
    expect(back.retryCount, 2);
    expect(back.tenantId, 'tenant-abc');
    expect(back.clientUpdatedAt, now);
    expect(back.createdAt, now);
    // El payload de sync sigue armándose bien tras el roundtrip.
    expect(back.toSyncPayload()['data'], {'total': 1500, 'items': 2});
  });
}
