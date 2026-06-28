// Spec: specs/087-splash-loader-animado/spec.md
//
// Revelado de logos "dibujándolos" por orden de trazo (cobertura 100%) con un
// fragment shader. VendIA es la constante; el resto entra al azar. Nativo,
// 60fps, web + móvil. Fail-safe: si el shader/asset falla, no rompe nada.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Carga (con caché) del shader y los assets de cada logo.
class SplashAssets {
  static const String vendia = 'vendia';
  static const List<String> all = [
    'vendia', 'cursor', 'cap', 'cutlery', 'store', 'burger', 'vaso',
    'cohete', 'camion', 'carrito', 'moto', 'l4599', 'l4594',
  ];
  static List<String> get others =>
      all.where((n) => n != vendia).toList(growable: false);

  static ui.FragmentProgram? _program;
  static final Map<String, ui.Image> _images = {};

  /// Prepara el shader. Devuelve null si no se pudo (fail-safe).
  static Future<ui.FragmentProgram?> program() async {
    if (_program != null) return _program;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/logo_reveal.frag');
    } catch (_) {
      _program = null;
    }
    return _program;
  }

  static Future<ui.Image> _img(String path) async {
    final cached = _images[path];
    if (cached != null) return cached;
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return _images[path] = frame.image;
  }

  /// (logo, mapaDeOrden) de un logo por nombre.
  static Future<(ui.Image, ui.Image)> load(String name) async =>
      (await _img('assets/splash/$name.png'),
       await _img('assets/splash/${name}_order.png'));

  /// Un logo al azar distinto de [exclude].
  static String randomOther(Random r, {String? exclude}) {
    final pool = others.where((n) => n != exclude).toList();
    return pool[r.nextInt(pool.length)];
  }
}

/// Estado de una capa visible en un instante (logo + progreso de dibujado/borrado).
@immutable
class RevealLayer {
  const RevealLayer(this.logo, this.order, this.progress, this.erase);
  final ui.Image logo;
  final ui.Image order;
  final double progress; // 0..1 dibujado
  final double erase;    // 0..1 borrado por la cola
}

class _RevealPainter extends CustomPainter {
  _RevealPainter(this.shader, this.layers);
  final ui.FragmentShader shader;
  final List<RevealLayer> layers;
  final double feather = 0.03;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in layers) {
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, l.progress)
        ..setFloat(3, l.erase)
        ..setFloat(4, feather)
        ..setImageSampler(0, l.logo)
        ..setImageSampler(1, l.order);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(covariant _RevealPainter old) =>
      old.layers != layers;
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
  ui.FragmentProgram? _program;
  final Map<String, (ui.Image, ui.Image)> _imgs = {};
  late final AnimationController _ctrl;
  late final List<double> _starts; // segundos
  late final double _total;        // segundos
  bool _ready = false;

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
    _program = await SplashAssets.program();
    for (final name in widget.logos.toSet()) {
      try {
        _imgs[name] = await SplashAssets.load(name);
      } catch (_) {/* fail-safe: ese logo no se pinta */}
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _ctrl.forward(from: 0);
  }

  List<RevealLayer> _layersAt(double t) {
    final out = <RevealLayer>[];
    for (var i = 0; i < widget.logos.length; i++) {
      final pair = _imgs[widget.logos[i]];
      if (pair == null) continue;
      final local = t - _starts[i];
      if (local < 0 || local > _d + _h + _e) continue;
      double prog, er;
      if (local < _d) {
        prog = local / _d;
        er = 0;
      } else if (local < _d + _h) {
        prog = 1;
        er = 0;
      } else {
        prog = 1;
        er = (local - _d - _h) / _e;
      }
      out.add(RevealLayer(pair.$1, pair.$2, _ease(prog), _ease(er)));
    }
    return out;
  }

  double _ease(double t) {
    t = t.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t); // smoothstep
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    // Fail-safe: sin shader/assets → logo VendIA estático (nunca pantalla rota).
    if (!_ready || program == null) {
      return Center(
        child: Image.asset('assets/images/vendia_icon_1024.png',
            width: 140, height: 140,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final layers = _layersAt(_ctrl.value * _total);
        return CustomPaint(
          painter: _RevealPainter(program.fragmentShader(), layers),
          size: Size.infinite,
        );
      },
    );
  }
}
