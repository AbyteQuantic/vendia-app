// Spec: specs/087-splash-loader-animado/spec.md
//
// Revelado de logos "dibujándolos" siguiendo el trazo, revelando el PNG real.
// SIN fragment shader → funciona en TODO navegador (Flutter web NO soporta image
// samplers en shaders). Usa PathMetrics (recorrido del trazo) + recorte de imagen
// (BlendMode.srcIn). VendIA es la constante; el resto entra al azar. Fail-safe total.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Datos de un logo: imagen nítida + recorrido del trazo (0..1) + grosor (0..1).
class LogoData {
  LogoData(this.image, this.path, this.pen);
  final ui.Image image;
  final ui.Path path;
  final double pen;
}

class SplashAssets {
  static const String vendia = 'vendia';

  /// Pool del splash/loader: logos cuyo trazo cubre ~100% (se ven completos con
  /// la técnica sin shader). Se excluyen los de relleno que el trazo no llena
  /// (vaso, moto, cutlery, cap, store) para que NUNCA salga incompleto.
  static const List<String> others = [
    'cursor', 'burger', 'camion', 'carrito', 'cohete', 'l4594', 'l4599',
  ];

  static Map<String, dynamic>? _paths;
  static final Map<String, LogoData> _cache = {};

  static Future<Map<String, dynamic>> _loadPaths() async {
    if (_paths != null) return _paths!;
    final raw = await rootBundle.loadString('assets/splash/splash_paths.json');
    return _paths = jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<ui.Image> _img(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  /// Carga (con caché) un logo: imagen + Path del trazo + grosor.
  static Future<LogoData> load(String name) async {
    final cached = _cache[name];
    if (cached != null) return cached;
    final paths = await _loadPaths();
    final entry = paths[name] as Map<String, dynamic>;
    final pen = (entry['pen'] as num).toDouble();
    final p = ui.Path();
    for (final sub in (entry['subs'] as List)) {
      final pts = sub as List;
      final a = pts[0] as List;
      p.moveTo((a[0] as num).toDouble(), (a[1] as num).toDouble());
      for (var i = 1; i < pts.length; i++) {
        final b = pts[i] as List;
        p.lineTo((b[0] as num).toDouble(), (b[1] as num).toDouble());
      }
    }
    final img = await _img('assets/splash/$name.png');
    return _cache[name] = LogoData(img, p, pen);
  }

  static String randomOther(Random r, {String? exclude}) {
    final pool = others.where((n) => n != exclude).toList();
    return pool[r.nextInt(pool.length)];
  }
}

/// Capa visible: logo + rango del trazo a mostrar [from..to] (0..1).
@immutable
class RevealLayer {
  const RevealLayer(this.data, this.from, this.to);
  final LogoData data;
  final double from;
  final double to;
}

class _RevealPainter extends CustomPainter {
  _RevealPainter(this.layers);
  final List<RevealLayer> layers;

  /// Porción del Path entre [from..to] recorriendo los subtrazos en orden.
  ui.Path _range(ui.Path src, double from, double to) {
    final out = ui.Path();
    final metrics = src.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    if (total <= 0) return out;
    final fromL = from * total, toL = to * total;
    double cum = 0;
    for (final m in metrics) {
      final s = cum, e = cum + m.length;
      final a = fromL.clamp(s, e) - s, b = toL.clamp(s, e) - s;
      if (b > a) out.addPath(m.extractPath(a, b), Offset.zero);
      cum = e;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side, side); // Path y grosor viven en 0..1
    const unit = Rect.fromLTWH(0, 0, 1, 1);
    for (final l in layers) {
      final drawn = _range(l.data.path, l.from, l.to);
      if (drawn.computeMetrics().isEmpty) continue;
      canvas.saveLayer(unit, Paint());
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.data.pen
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFFFFFFFF),
      );
      final img = l.data.image;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        unit,
        Paint()..blendMode = BlendMode.srcIn,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RevealPainter old) => old.layers != layers;
}

/// Reproduce una secuencia de logos que se dibujan (encadenados). Reusable por
/// el splash (1 vez) y el loader (en bucle).
class LogoSequenceReveal extends StatefulWidget {
  const LogoSequenceReveal({
    super.key,
    required this.logos,
    this.draw = const Duration(milliseconds: 1100),
    this.hold = const Duration(milliseconds: 1100),
    this.erase = const Duration(milliseconds: 700),
    this.overlap = const Duration(milliseconds: 250),
    this.loop = false,
    this.onDone,
  });

  final List<String> logos;
  final Duration draw, hold, erase, overlap;
  final bool loop;
  final VoidCallback? onDone;

  @override
  State<LogoSequenceReveal> createState() => _LogoSequenceRevealState();
}

class _LogoSequenceRevealState extends State<LogoSequenceReveal>
    with SingleTickerProviderStateMixin {
  /// Tope de carga de assets (bug prod 2026-07-08, web): si el fetch del
  /// json/PNG se cuelga, la animación jamás arrancaba y el splash quedaba en
  /// blanco. Pasado este tope se arranca con lo que haya cargado o se degrada
  /// al logo ESTÁTICO (fail-safe Spec 087) y `onDone` igual se dispara para
  /// que el flujo continúe. Timer cancelable (no `.timeout`) para no dejar
  /// timers huérfanos al desmontar.
  static const _bootTimeout = Duration(seconds: 3);

  final Map<String, LogoData> _data = {};
  late final AnimationController _ctrl;
  late final List<double> _starts;
  late final double _total;
  bool _ready = false;
  bool _started = false;
  bool _fallback = false;
  Timer? _bootGuard;
  Timer? _fallbackDone;

  double get _d => widget.draw.inMilliseconds / 1000;
  double get _h => widget.hold.inMilliseconds / 1000;
  double get _e => widget.erase.inMilliseconds / 1000;
  double get _ov => widget.overlap.inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    final adv = _d + _h + _e - _ov;
    _starts = [for (var i = 0; i < widget.logos.length; i++) i * adv];
    _total = _starts.last + _d + _h + _e;
    _ctrl = AnimationController(
        vsync: this, duration: Duration(milliseconds: (_total * 1000).round()));
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        if (widget.loop) {
          _ctrl.forward(from: 0);
        } else {
          widget.onDone?.call();
        }
      }
    });
    _boot();
  }

  Future<void> _boot() async {
    _bootGuard = Timer(_bootTimeout, _bootFailSafe);
    for (final name in widget.logos.toSet()) {
      try {
        _data[name] = await SplashAssets.load(name);
      } catch (_) {/* fail-safe: ese logo no se pinta */}
    }
    _bootGuard?.cancel();
    if (!mounted || _started) return;
    if (_data.isEmpty) {
      _showStaticFallback();
      return;
    }
    _start();
  }

  /// Venció [_bootTimeout] con la carga colgada: arranca con lo que haya
  /// cargado, o degrada al logo estático si no cargó nada.
  void _bootFailSafe() {
    if (!mounted || _started) return;
    if (_data.isNotEmpty) {
      _start();
      return;
    }
    _showStaticFallback();
  }

  void _start() {
    _started = true;
    setState(() => _ready = true);
    _ctrl.forward(from: 0);
  }

  /// Fail-safe total (Spec 087): sin trazos no hay animación — logo estático
  /// y el flujo (onDone) continúa para no atascar el splash.
  void _showStaticFallback() {
    _started = true;
    setState(() {
      _ready = true;
      _fallback = true;
    });
    if (!widget.loop) {
      _fallbackDone = Timer(widget.hold, () {
        if (mounted) widget.onDone?.call();
      });
    }
  }

  double _ease(double t) {
    t = t.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  List<RevealLayer> _layersAt(double t) {
    final out = <RevealLayer>[];
    for (var i = 0; i < widget.logos.length; i++) {
      final d = _data[widget.logos[i]];
      if (d == null) continue;
      final local = t - _starts[i];
      if (local < 0 || local > _d + _h + _e) continue;
      if (local < _d) {
        out.add(RevealLayer(d, 0, _ease(local / _d)));
      } else if (local < _d + _h) {
        out.add(RevealLayer(d, 0, 1));
      } else {
        out.add(RevealLayer(d, _ease((local - _d - _h) / _e), 1));
      }
    }
    return out;
  }

  @override
  void dispose() {
    _bootGuard?.cancel();
    _fallbackDone?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mientras carga: nada (blanco). NO mostramos el ícono estático oscuro.
    if (!_ready) return const SizedBox.shrink();
    if (_fallback) {
      // Logo estático (mismo asset del primer logo de la secuencia). Si ni
      // siquiera la imagen carga, se queda en blanco pero el flujo ya sigue.
      return Image.asset(
        'assets/splash/${widget.logos.first}.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _RevealPainter(_layersAt(_ctrl.value * _total)),
        size: Size.infinite,
      ),
    );
  }
}
