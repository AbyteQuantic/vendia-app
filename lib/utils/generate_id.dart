import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generate a UUID v4 for any entity. NEVER let the server generate the ID.
String generateId() => _uuid.v4();
