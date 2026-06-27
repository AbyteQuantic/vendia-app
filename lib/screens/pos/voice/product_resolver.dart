// Spec: specs/085-vender-por-voz/spec.md
//
// Resolución PURA del nombre HABLADO → Product real. Sin red, sin estado:
// testeable con catálogos sembrados. Reusa foldKey (quita tildes/case/espacios)
// de text_normalize.dart — la búsqueda del POS no normaliza tildes, así que el
// camino de voz DEBE pasar por foldKey o falla con acentos.

import '../../../models/product.dart';
import '../../../utils/text_normalize.dart';

enum ResolveStatus { matched, ambiguous, notFound }

class ProductResolution {
  final ResolveStatus status;
  final String spokenName;
  final Product? product; // sólo en matched
  final List<Product> candidates; // top-N en ambiguous

  const ProductResolution({
    required this.status,
    required this.spokenName,
    this.product,
    this.candidates = const [],
  });
}

class ProductResolver {
  final double strongScore;
  final double minScore;
  final double margin;

  const ProductResolver({
    this.strongScore = 0.6,
    this.minScore = 0.34,
    this.margin = 0.15,
  });

  /// Resuelve [spokenName] contra [catalog]. Excluye productos sin precio
  /// (price<=0) o no disponibles — la voz nunca ofrece algo invendible.
  ProductResolution resolve(String spokenName, List<Product> catalog) {
    final spoken = foldKey(spokenName);
    if (spoken.isEmpty) {
      return ProductResolution(status: ResolveStatus.notFound, spokenName: spokenName);
    }
    final pool = catalog
        .where((p) => p.price > 0 && p.isAvailable && p.name.trim().isNotEmpty)
        .toList();

    // Paso 1 — exacto.
    final exact = pool.where((p) => foldKey(p.name) == spoken).toList();
    if (exact.length == 1) {
      return ProductResolution(
          status: ResolveStatus.matched, spokenName: spokenName, product: exact.first);
    }
    if (exact.length > 1) {
      return ProductResolution(
          status: ResolveStatus.ambiguous,
          spokenName: spokenName,
          candidates: exact.take(3).toList());
    }

    // Paso 2 — contains en cualquier dirección.
    final contains = pool.where((p) {
      final n = foldKey(p.name);
      return n.contains(spoken) || spoken.contains(n);
    }).toList();
    if (contains.length == 1) {
      return ProductResolution(
          status: ResolveStatus.matched, spokenName: spokenName, product: contains.first);
    }

    // Paso 3 — score por tokens (coeficiente de Dice) sobre el subconjunto
    // contains si lo hay, si no sobre todo el pool.
    final scoringPool = contains.isNotEmpty ? contains : pool;
    final spokenTokens = _tokens(spoken);
    final scored = scoringPool
        .map((p) => (p: p, score: _dice(spokenTokens, _tokens(foldKey(p.name)))))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      return ProductResolution(status: ResolveStatus.notFound, spokenName: spokenName);
    }
    final best = scored.first.score;
    final second = scored.length > 1 ? scored[1].score : 0.0;

    if (best >= strongScore && (best - second) >= margin) {
      return ProductResolution(
          status: ResolveStatus.matched, spokenName: spokenName, product: scored.first.p);
    }
    if (best >= minScore) {
      return ProductResolution(
        status: ResolveStatus.ambiguous,
        spokenName: spokenName,
        candidates: scored.where((e) => e.score >= minScore).take(3).map((e) => e.p).toList(),
      );
    }
    return ProductResolution(status: ResolveStatus.notFound, spokenName: spokenName);
  }

  Set<String> _tokens(String folded) =>
      folded.split(' ').where((t) => t.isNotEmpty).toSet();

  /// Coeficiente de Dice = 2·|A∩B| / (|A|+|B|). 0..1.
  double _dice(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    return (2.0 * inter) / (a.length + b.length);
  }
}
