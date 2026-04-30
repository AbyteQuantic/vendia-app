import '../database/collections/local_product.dart';

/// Result of matching an extracted product name against the local catalog.
class MatchResult {
  final LocalProduct product;
  final double score;

  const MatchResult({required this.product, required this.score});
}

/// Normalize a product name for fuzzy comparison:
/// lowercase, trim, remove diacritics, collapse whitespace.
String normalize(String input) {
  var s = input.toLowerCase().trim();
  // Remove common diacritics
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  for (var i = 0; i < from.length; i++) {
    s = s.replaceAll(from[i], to[i]);
  }
  // Collapse multiple spaces into one
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s;
}

/// Score how similar two normalized names are (0.0 – 1.0).
double _score(String a, String b) {
  if (a == b) return 1.0;
  if (a.contains(b) || b.contains(a)) return 0.8;
  // Jaccard on word tokens
  final tokA = a.split(' ').toSet();
  final tokB = b.split(' ').toSet();
  if (tokA.isEmpty || tokB.isEmpty) return 0.0;
  final inter = tokA.intersection(tokB).length;
  final union = tokA.union(tokB).length;
  return inter / union;
}

/// Find the best matching product from [catalog] for [extractedName].
/// Returns null if no match scores >= [threshold] (default 0.5).
MatchResult? findBestMatch(
  String extractedName,
  List<LocalProduct> catalog, {
  double threshold = 0.5,
}) {
  final norm = normalize(extractedName);
  if (norm.isEmpty) return null;

  MatchResult? best;
  for (final p in catalog) {
    final s = _score(norm, normalize(p.name));
    if (s >= threshold && (best == null || s > best.score)) {
      best = MatchResult(product: p, score: s);
    }
  }
  return best;
}
