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

/// Spec 099 (FR-09/AC-09): una fila del importador de productos que no
/// coincidió exactamente (barcode o nombre normalizado) pero se parece a
/// un producto ya existente — informativo únicamente, nunca bloquea ni
/// fusiona la fila en silencio. Ausente por completo en respuestas del
/// importador de clientes (Spec 026).
class FuzzyMatchInfo {
  final int rowIndex;
  final String rowName;
  final String candidateId;
  final String candidateName;
  final double similarity;

  const FuzzyMatchInfo({
    required this.rowIndex,
    required this.rowName,
    required this.candidateId,
    required this.candidateName,
    required this.similarity,
  });

  factory FuzzyMatchInfo.fromJson(Map<String, dynamic> json) => FuzzyMatchInfo(
        rowIndex: (json['row_index'] as num?)?.toInt() ?? 0,
        rowName: json['row_name'] as String? ?? '',
        candidateId: json['candidate_id'] as String? ?? '',
        candidateName: json['candidate_name'] as String? ?? '',
        similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      );
}

/// Resultado agregado de importar uno o más chunks de clientes o productos.
class ImportReport {
  final int created;
  final int updated;
  final int skipped;
  final List<ImportFailure> failed;
  final List<FuzzyMatchInfo> fuzzyMatches;

  const ImportReport({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.fuzzyMatches = const [],
  });

  const ImportReport.empty()
      : created = 0,
        updated = 0,
        skipped = 0,
        failed = const [],
        fuzzyMatches = const [];

  factory ImportReport.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final failedList = (data['failed'] as List<dynamic>? ?? [])
        .map((e) => ImportFailure.fromJson(e as Map<String, dynamic>))
        .toList();
    final fuzzyList = (data['fuzzy_matches'] as List<dynamic>? ?? [])
        .map((e) => FuzzyMatchInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return ImportReport(
      created: (data['created'] as num?)?.toInt() ?? 0,
      updated: (data['updated'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      failed: failedList,
      fuzzyMatches: fuzzyList,
    );
  }

  /// Suma este reporte con otro chunk.
  ImportReport merge(ImportReport other) => ImportReport(
        created: created + other.created,
        updated: updated + other.updated,
        skipped: skipped + other.skipped,
        failed: [...failed, ...other.failed],
        fuzzyMatches: [...fuzzyMatches, ...other.fuzzyMatches],
      );
}
