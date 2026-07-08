// Spec: specs/099-inventario-voz-factura-campos-separados/spec.md
//
// fuzzy_matches (FR-09/AC-09): rows the CSV importer didn't merge
// exactly but resemble an existing product — informational only, never
// blocks the import, never auto-merges.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/import_report.dart';

void main() {
  test('fromJson parses fuzzy_matches when present', () {
    final report = ImportReport.fromJson({
      'data': {
        'created': 1,
        'updated': 0,
        'skipped': 0,
        'failed': [],
        'fuzzy_matches': [
          {
            'row_index': 0,
            'row_name': 'Coca Cola 350 ml',
            'candidate_id': 'p-1',
            'candidate_name': 'Coca-Cola 350ml',
            'similarity': 0.82,
          }
        ],
      }
    });

    expect(report.fuzzyMatches, hasLength(1));
    expect(report.fuzzyMatches.first.rowName, 'Coca Cola 350 ml');
    expect(report.fuzzyMatches.first.candidateName, 'Coca-Cola 350ml');
    expect(report.fuzzyMatches.first.similarity, 0.82);
  });

  test('fromJson defaults fuzzy_matches to empty when absent — customer '
      'import responses never carry this field', () {
    final report = ImportReport.fromJson({
      'data': {'created': 1, 'updated': 0, 'skipped': 0, 'failed': []}
    });

    expect(report.fuzzyMatches, isEmpty);
  });

  test('merge concatenates fuzzy_matches across chunks', () {
    const a = ImportReport(
      created: 1,
      updated: 0,
      skipped: 0,
      failed: [],
      fuzzyMatches: [
        FuzzyMatchInfo(
            rowIndex: 0,
            rowName: 'A',
            candidateId: 'p1',
            candidateName: 'A2',
            similarity: 0.7)
      ],
    );
    const b = ImportReport(
      created: 1,
      updated: 0,
      skipped: 0,
      failed: [],
      fuzzyMatches: [
        FuzzyMatchInfo(
            rowIndex: 1,
            rowName: 'B',
            candidateId: 'p2',
            candidateName: 'B2',
            similarity: 0.8)
      ],
    );

    final merged = a.merge(b);
    expect(merged.fuzzyMatches, hasLength(2));
  });

  test('empty() has no fuzzy matches', () {
    const report = ImportReport.empty();
    expect(report.fuzzyMatches, isEmpty);
  });
}
