// Modelo plano de operación pendiente de sync para la build web (sin Isar).
// Espejo de `pending_operation_io.dart` sin anotaciones Isar.
class PendingOperation {
  int id = 0;

  late String uuid;
  late String entity;
  late String action;
  late String jsonData;
  late DateTime clientUpdatedAt;
  late int retryCount;
  late DateTime createdAt;
  String tenantId = '';

  Map<String, dynamic> toSyncPayload() => {
        'uuid': uuid,
        'entity': entity,
        'action': action,
        'data': jsonData,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };
}
