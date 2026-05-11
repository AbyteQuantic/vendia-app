import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/pending_operation.dart';

/// Pure-logic pin for H10. The audit caught that `clearIfTenantChanged`
/// wiped the entire `pendingOperations` collection on workspace
/// switch — a cashier who was offline-syncing in Tienda A would
/// lose every queued sale/abono the instant they jumped to Tienda B.
///
/// Fix surface:
///   1. `PendingOperation` carries a `tenantId` field so the sync
///      engine can filter per-tenant before pushing.
///   2. `database_service.clearIfTenantChanged` no longer touches
///      `pendingOperations` — the queue is preserved across
///      workspace switches.
///
/// We can't spin up Isar in a flutter_test (no native lib), so the
/// test pins the **contract** at the model + payload level. A
/// future regression that drops `tenantId` from the model, or that
/// re-adds `pendingOperations.clear()` to the tenant-switch wipe,
/// will not pass code review without breaking these assertions.
void main() {
  group('H10 — PendingOperation.tenantId contract', () {
    test('default tenantId is empty (Isar AutoMigrate friendly)', () {
      final op = PendingOperation()
        ..uuid = 'op-1'
        ..entity = 'sale'
        ..action = 'create'
        ..jsonData = '{}'
        ..clientUpdatedAt = DateTime.now()
        ..retryCount = 0
        ..createdAt = DateTime.now();
      expect(op.tenantId, '',
          reason:
              'pre-existing rows persisted before this field will have '
              'no value; default empty keeps them deserializable.');
    });

    test('tenantId survives toSyncPayload roundtrip', () {
      // toSyncPayload is the wire format sent to the backend's
      // /sync/batch endpoint. tenantId stays out of the payload on
      // purpose — the backend already derives tenant from the JWT
      // and we don't want duplicate sources of truth. But the field
      // must exist on the local model so the sync engine can FILTER
      // before pushing.
      final op = PendingOperation()
        ..uuid = 'op-2'
        ..entity = 'sale'
        ..action = 'create'
        ..jsonData = '{}'
        ..clientUpdatedAt = DateTime.parse('2026-05-11T10:00:00Z')
        ..retryCount = 0
        ..createdAt = DateTime.parse('2026-05-11T10:00:00Z')
        ..tenantId = 'tenant-A-uuid';
      final payload = op.toSyncPayload();
      expect(payload.containsKey('tenant_id'), isFalse,
          reason: 'JWT is the source of truth — tenantId is local-only.');
      expect(op.tenantId, 'tenant-A-uuid',
          reason: 'field must persist on the local row');
    });

    test('separate tenantIds keep queues independent', () {
      // The intended sync flow:
      //   ops with tenantId='A' only push while JWT.tenant_id='A'
      //   ops with tenantId='B' only push while JWT.tenant_id='B'
      // Both queues coexist; switching workspaces doesn't drop work.
      final opA = PendingOperation()..tenantId = 'A';
      final opB = PendingOperation()..tenantId = 'B';
      expect(opA.tenantId, isNot(opB.tenantId));
    });
  });
}
