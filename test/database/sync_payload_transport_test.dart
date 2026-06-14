// Spec: specs/047-offline-sync-contract/spec.md (AC-01)
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/pending_operation.dart';

void main() {
  test('toSyncPayload["data"] es un Map (no String) — AC-01', () {
    final op = PendingOperation()
      ..uuid = 'op-1'
      ..entity = 'credit_account'
      ..action = 'create'
      ..jsonData = jsonEncode({'customer_id': 'c-1', 'total_amount': 5000})
      ..clientUpdatedAt = DateTime(2026)
      ..retryCount = 0
      ..createdAt = DateTime(2026);

    final payload = op.toSyncPayload();

    expect(payload['data'], isA<Map<String, dynamic>>());
    expect((payload['data'] as Map)['customer_id'], 'c-1');
    expect((payload['data'] as Map)['total_amount'], 5000);
  });

  test('el envelope manda la PK bajo "id" (el backend la exige, no "uuid")', () {
    final op = PendingOperation()
      ..uuid = 'op-9'
      ..entity = 'customer'
      ..action = 'create'
      ..jsonData = '{}'
      ..clientUpdatedAt = DateTime(2026)
      ..retryCount = 0
      ..createdAt = DateTime(2026);

    final payload = op.toSyncPayload();
    expect(payload['id'], 'op-9');
    // No debe quedar la llave vieja que el backend ignora.
    expect(payload.containsKey('uuid'), isFalse);
  });

  test('jsonData vacío produce un mapa vacío, no rompe', () {
    final op = PendingOperation()
      ..uuid = 'op-2'
      ..entity = 'customer'
      ..action = 'create'
      ..jsonData = ''
      ..clientUpdatedAt = DateTime(2026)
      ..retryCount = 0
      ..createdAt = DateTime(2026);

    expect(op.toSyncPayload()['data'], <String, dynamic>{});
  });
}
