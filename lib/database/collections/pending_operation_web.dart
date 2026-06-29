// Modelo plano de operación pendiente de sync para la build web (sin Isar).
// Espejo de `pending_operation_io.dart` sin anotaciones Isar.
import 'dart:convert';

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
        // El backend exige la PK bajo `id` (no `uuid`). Ver io variant.
        'id': uuid,
        'entity': entity,
        'action': action,
        // AC-01: data como objeto, no String (ver pending_operation_io.dart).
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

  // Spec 092: persistencia offline en web (localStorage). Serializa TODOS los
  // campos para sobrevivir a un refresh, no solo el payload de sync.
  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'entity': entity,
        'action': action,
        'jsonData': jsonData,
        'clientUpdatedAt': clientUpdatedAt.toIso8601String(),
        'retryCount': retryCount,
        'createdAt': createdAt.toIso8601String(),
        'tenantId': tenantId,
      };

  static PendingOperation fromJson(Map<String, dynamic> j) {
    return PendingOperation()
      ..id = (j['id'] as num?)?.toInt() ?? 0
      ..uuid = j['uuid'] as String? ?? ''
      ..entity = j['entity'] as String? ?? ''
      ..action = j['action'] as String? ?? ''
      ..jsonData = j['jsonData'] as String? ?? ''
      ..clientUpdatedAt =
          DateTime.tryParse(j['clientUpdatedAt'] as String? ?? '') ??
              DateTime.now()
      ..retryCount = (j['retryCount'] as num?)?.toInt() ?? 0
      ..createdAt =
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now()
      ..tenantId = j['tenantId'] as String? ?? '';
  }
}
