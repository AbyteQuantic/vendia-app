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
  ///
  /// Antes de comparar, el nombre HABLADO se limpia (quita verbos de venta y
  /// artículos: "vendo/deme/para/la…") y tanto el hablado como el del catálogo
  /// se "despluralizan" por token (empanadas→empanada, panes→pan, aguas→agua).
  /// Así "vendo 3 empanadas" encuentra el producto guardado como "Empanada".
  /// El deplural es SIMÉTRICO (se aplica a los dos lados) y nunca borra
  /// palabras de contenido — "con gas" y "sin gas" siguen siendo distintos.
  ProductResolution resolve(String spokenName, List<Product> catalog) {
    final spoken = _foldSpoken(spokenName);
    if (spoken.isEmpty) {
      return ProductResolution(status: ResolveStatus.notFound, spokenName: spokenName);
    }
    final pool = catalog
        .where((p) => p.price > 0 && p.isAvailable && p.name.trim().isNotEmpty)
        .toList();

    // Paso 1 — exacto (sobre la forma despluralizada de ambos lados).
    final exact = pool.where((p) => _foldName(p.name) == spoken).toList();
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
      final n = _foldName(p.name);
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
        .map((p) => (p: p, score: _dice(spokenTokens, _tokens(_foldName(p.name)))))
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

  /// Nombre del catálogo → clave de comparación: foldKey + quita conectores
  /// vacíos de contenido (de/la/para…) + despluraliza cada token.
  String _foldName(String name) => _clean(foldKey(name), _connectors);

  /// Nombre HABLADO → clave de comparación: además de lo de [_foldName], quita
  /// los verbos de venta que suele colar el tendero ("vendo/deme/quiero…").
  String _foldSpoken(String spoken) => _clean(foldKey(spoken), _spokenNoise);

  String _clean(String folded, Set<String> drop) {
    final toks = folded
        .split(' ')
        .where((t) => t.isNotEmpty && !drop.contains(t))
        .map(_deplural)
        .where((t) => t.isNotEmpty)
        .toList();
    return toks.join(' ');
  }

  /// Despluraliza un token en español de forma conservadora. SIMÉTRICO: se
  /// aplica al hablado y al catálogo, así que basta con acercar las formas
  /// (no busca el singular "correcto"). Umbrales de longitud evitan destrozar
  /// palabras cortas de contenido ("gas"→"gas", "mas"→"mas", "tres"→"tres").
  String _deplural(String t) {
    if (t.length > 4 && t.endsWith('es')) return t.substring(0, t.length - 2);
    if (t.length > 3 && t.endsWith('s')) return t.substring(0, t.length - 1);
    return t;
  }

  /// Conectores sin contenido — seguros de borrar en AMBOS lados. NO incluye
  /// "con"/"sin"/"gas" ni nada que distinga productos.
  static const Set<String> _connectors = {
    'de', 'del', 'la', 'el', 'los', 'las', 'un', 'una', 'unos', 'unas',
    'lo', 'al', 'para', 'y', 'e', 'o',
  };

  /// Ruido que sólo aparece en lo HABLADO: conectores + verbos/muletillas de
  /// venta. Se quita del hablado para que "vendo/deme/quiero X" resuelva a X.
  static const Set<String> _spokenNoise = {
    ..._connectors,
    'vendo', 'venda', 'vende', 'vendame', 'vendeme', 'vender',
    'deme', 'dame', 'quiero', 'lleva', 'llevo', 'llevar',
    'echeme', 'eche', 'agregue', 'agrega', 'agregame', 'anada', 'anade',
    'pongame', 'ponga', 'pon', 'me', 'mas', 'otra', 'otro', 'por', 'favor',
  };

  /// Coeficiente de Dice = 2·|A∩B| / (|A|+|B|). 0..1.
  double _dice(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    return (2.0 * inter) / (a.length + b.length);
  }
}
