// Spec: specs/026-importador-clientes/spec.md

/// Describe un fallo individual en la importación.
class ImportFailure {
  final int rowIndex;
  final String reason;

  const ImportFailure({required this.rowIndex, required this.reason});

  factory ImportFailure.fromJson(Map<String, dynamic> json) => ImportFailure(
        rowIndex: (json['row_index'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
      );

  @override
  String toString() => 'Fila ${rowIndex + 1}: $reason';
}

/// Resultado agregado de importar uno o más chunks de clientes.
class ImportReport {
  final int created;
  final int updated;
  final int skipped;
  final List<ImportFailure> failed;

  const ImportReport({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failed,
  });

  const ImportReport.empty()
      : created = 0,
        updated = 0,
        skipped = 0,
        failed = const [];

  factory ImportReport.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final failedList = (data['failed'] as List<dynamic>? ?? [])
        .map((e) => ImportFailure.fromJson(e as Map<String, dynamic>))
        .toList();
    return ImportReport(
      created: (data['created'] as num?)?.toInt() ?? 0,
      updated: (data['updated'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      failed: failedList,
    );
  }

  /// Suma este reporte con otro chunk.
  ImportReport merge(ImportReport other) => ImportReport(
        created: created + other.created,
        updated: updated + other.updated,
        skipped: skipped + other.skipped,
        failed: [...failed, ...other.failed],
      );
}
