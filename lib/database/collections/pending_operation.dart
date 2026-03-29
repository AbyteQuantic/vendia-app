import 'package:isar/isar.dart';

part 'pending_operation.g.dart';

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

  Map<String, dynamic> toSyncPayload() => {
        'uuid': uuid,
        'entity': entity,
        'action': action,
        'data': jsonData,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
      };
}
