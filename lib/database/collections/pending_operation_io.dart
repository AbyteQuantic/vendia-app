import 'package:isar/isar.dart';

part 'pending_operation_io.g.dart';

@collection
class PendingOperation {
  Id id = Isar.autoIncrement;

  late String uuid;
  @Index()
  late String entity;
  late String action;
  late String jsonData;
  late DateTime clientUpdatedAt;
  late int retryCount;
  late DateTime createdAt;

  /// Tenant the operation was authored under. Indexed so the sync
  /// engine can filter the queue to "only mine" before pushing —
  /// without this, a cashier who switches workspaces would either
  /// (a) lose their queued ops (the old `clearIfTenantChanged`
  /// wipe), or (b) leak ops from tenant A through the JWT of
  /// tenant B once they re-login (the backend would reject, but
  /// the local queue would keep retrying forever).
  ///
  /// Default empty string covers two cases: rows persisted before
  /// this field existed (Isar AutoMigrate fills with ''), and
  /// pre-login bootstrap where there's no tenant yet.
  @Index()
  String tenantId = '';

  Map<String, dynamic> toSyncPayload() => {
        'uuid': uuid,
        'entity': entity,
        'action': action,
        'data': jsonData,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };
}
