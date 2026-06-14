import 'dart:convert';
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
        // El backend espera la PK del lote bajo la llave `id`
        // (SyncOperation.ID, binding:"required"). Mandar `uuid` deja `ID`
        // vacío → 400 de todo el lote y, aun pasando, PK vacía en el insert.
        'id': uuid,
        'entity': entity,
        'action': action,
        // AC-01: el backend espera `data` como objeto (map[string]any), no como
        // String. `jsonData` se guarda serializado para Isar; aquí se decodifica
        // antes de mandarlo o el bind del lote falla con 400.
        'data': _decodedData(),
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };

  Map<String, dynamic> _decodedData() {
    if (jsonData.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(jsonData);
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }
}
