// Spec: specs/106-onboarding-conversacional-agente/spec.md (Adenda OS1)
//
// VendiOrb — el símbolo vivo de Vendi, dirección visual "Her/OS1" aprobada
// por el fundador (2026-07-19): un trazo continuo FINO (1.6px) que respira en
// reposo (la palomilla ∞) y se transforma con morphing fluido en silueta,
// teléfono, candado, tienda o corazón según lo que se pregunta.
//
// Motor idéntico al prototipo aprobado: cada forma son N puntos re-muestreados
// por longitud de arco desde anclas limpias (sin auto-cruces); el morph
// interpola punto a punto tras alinear offset/orientación; el trazo se pinta
// como curva cuadrática entre puntos medios (sin facetas) en dos pasadas:
// halo sutil + línea nítida. Liviano para Android de gama baja: un solo
// CustomPaint, cero shaders, cero imágenes.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../theme/app_theme.dart';

enum VendiOrbShape { palomilla, user, phone, lock, store, heart }

const int _kN = 160;
const double _kTau = math.pi * 2;

class VendiOrb extends StatefulWidget {
  const VendiOrb({
    super.key,
    required this.shape,
    this.size = 200,
    this.listening = false,
  });

  final VendiOrbShape shape;
  final double size;

  /// Ondula más fuerte mientras el tendero escribe/habla.
  final bool listening;

  @override
  State<VendiOrb> createState() => _VendiOrbState();
}

// TickerProvider normal (no Single): este State crea DOS tickers — el del
// morph y el de la vida/ondulación permanente.
class _VendiOrbState extends State<VendiOrb> with TickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  Ticker? _life;
  final ValueNotifier<double> _t = ValueNotifier(0); // segundos de vida

  late List<Offset> _from;
  late List<Offset> _to;

  @override
  void initState() {
    super.initState();
    _from = List.of(_VendiShapes.of(widget.shape));
    _to = List.of(_from);
    _morph.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduce && _life == null) {
      _life = createTicker((elapsed) {
        _t.value = elapsed.inMicroseconds / 1e6;
      })..start();
    }
  }

  @override
  void didUpdateWidget(covariant VendiOrb old) {
    super.didUpdateWidget(old);
    if (old.shape != widget.shape) {
      _from = _currentPoints();
      _to = _VendiShapes.aligned(_from, _VendiShapes.of(widget.shape));
      _morph.forward(from: 0);
    }
  }

  List<Offset> _currentPoints() {
    final k = Curves.easeInOutCubic.transform(_morph.value);
    return List.generate(
      _kN,
      (i) => Offset.lerp(_from[i], _to[i], k)!,
      growable: false,
    );
  }

  @override
  void dispose() {
    _life?.dispose();
    _morph.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbPainter(
          from: _from,
          to: _to,
          morph: _morph,
          time: _t,
          isIcon: widget.shape != VendiOrbShape.palomilla,
          listening: widget.listening,
          repaint: Listenable.merge([_morph, _t]),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.from,
    required this.to,
    required this.morph,
    required this.time,
    required this.isIcon,
    required this.listening,
    required super.repaint,
  });

  final List<Offset> from;
  final List<Offset> to;
  final Animation<double> morph;
  final ValueNotifier<double> time;
  final bool isIcon;
  final bool listening;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(size.width, size.height) * .40;
    final k = Curves.easeInOutCubic.transform(morph.value);
    final now = time.value;

    // Vida: la palomilla respira amplio; los íconos definidos apenas laten.
    final amp = isIcon ? .007 : .016;
    final settled = morph.isCompleted || morph.value == 1;
    final breathe = amp * 1.6 * math.sin(now / 1.05);
    final wobAmp = (settled ? amp : 0) + (listening ? .03 : 0);

    // Ondulación de BAJA frecuencia: 2 ondas suaves recorren el contorno.
    final p = List<Offset>.generate(_kN, (j) {
      final a = from[j], b = to[j];
      final x = a.dx + (b.dx - a.dx) * k;
      final y = a.dy + (b.dy - a.dy) * k;
      final s = 1 + breathe + wobAmp * math.sin(now / 1.1 + (j / _kN) * _kTau * 2);
      // y matemática (arriba positivo) → canvas (abajo positivo)
      return Offset(cx + x * s * r, cy - y * s * r);
    }, growable: false);

    // Curva CERRADA y SUAVE: cuadráticas entre puntos medios (sin facetas).
    final path = Path();
    Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    var m = mid(p[_kN - 1], p[0]);
    path.moveTo(m.dx, m.dy);
    for (var j = 0; j < _kN; j++) {
      final nm = mid(p[j], p[(j + 1) % _kN]);
      path.quadraticBezierTo(p[j].dx, p[j].dy, nm.dx, nm.dy);
    }
    path.close();

    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppTheme.accent, AppTheme.primary],
    );
    final shader = gradient.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

    // Pasada 1 — halo sutil (ancho, casi transparente, sin blur pesado).
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..shader = shader
      // El alpha del color modula el shader → halo casi transparente.
      ..color = Colors.white.withValues(alpha: .14);
    canvas.drawPath(path, halo);

    // Pasada 2 — la LÍNEA: fina y de borde nítido.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawPath(path, line);

    // Pasada 3 — destello viajero: un tramo (~20%) del contorno brilla y
    // recorre la forma lenta y suavemente (~6s por vuelta) — la señal de
    // que Vendi está "pensando"/viva incluso cuando el trazo reposa.
    final glowLen = (_kN * .20).round();
    final start = ((now / 6.0) % 1.0 * _kN).floor();
    final glowPath = Path();
    for (var i = 0; i <= glowLen; i++) {
      final pt = p[(start + i) % _kN];
      i == 0 ? glowPath.moveTo(pt.dx, pt.dy) : glowPath.lineTo(pt.dx, pt.dy);
    }
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.accent.withValues(alpha: .55);
    canvas.drawPath(glowPath, glow);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.from != from || old.to != to || old.listening != listening;
}

// ── Formas: anclas limpias → re-muestreo por arco (idéntico al prototipo) ───
class _VendiShapes {
  static final Map<VendiOrbShape, List<Offset>> _cache = _build();

  static List<Offset> of(VendiOrbShape s) => _cache[s]!;

  static Map<VendiOrbShape, List<Offset>> _build() {
    List<Offset> arc(double cx, double cy, double r, double a0deg,
        double a1deg, int steps) {
      final a0 = a0deg * math.pi / 180, a1 = a1deg * math.pi / 180;
      return List.generate(steps + 1, (i) {
        final a = a0 + (a1 - a0) * (i / steps);
        return Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      });
    }

    // La palomilla: el CHULO del OK — el mismo vector del logo de VendIA.
    // Contorno cerrado con grosor (silueta del check); las esquinas se
    // redondean solas por el suavizado de curvas del painter.
    const palomilla = <Offset>[
      Offset(-.60, .26),  // tope del brazo corto
      Offset(-.16, -.16), // codo interior
      Offset(.58, .64),   // subida del brazo largo
      Offset(.84, .40),   // punta exterior
      Offset(-.17, -.62), // codo exterior (vértice del chulo)
      Offset(-.84, .02),  // punta del brazo corto
    ];

    final user = <Offset>[
      ...arc(0, .34, .32, 245, -65, 48), // cabeza (gira por la cima)
      const Offset(.24, -.02), const Offset(.46, -.14), const Offset(.60, -.32),
      const Offset(.65, -.52), const Offset(.66, -.66), // hombro derecho
      const Offset(.44, -.70), const Offset(0, -.72), const Offset(-.44, -.70),
      const Offset(-.66, -.66), const Offset(-.65, -.52), const Offset(-.60, -.32),
      const Offset(-.46, -.14), const Offset(-.24, -.02), // hombro izquierdo
    ];

    final phone = <Offset>[
      ...arc(-.30, .72, .14, 90, 180, 10),
      const Offset(-.44, 0),
      ...arc(-.30, -.72, .14, 180, 270, 10),
      const Offset(.30, -.86),
      ...arc(.30, -.72, .14, 270, 360, 10),
      const Offset(.44, 0),
      ...arc(.30, .72, .14, 0, 90, 10),
      const Offset(-.30, .86),
    ];

    final lock = <Offset>[
      const Offset(-.55, .10), const Offset(-.55, -.60),
      ...arc(-.43, -.60, .12, 180, 270, 8),
      const Offset(.43, -.72),
      ...arc(.43, -.60, .12, 270, 360, 8),
      const Offset(.55, .10),
      const Offset(.34, .10), const Offset(.34, .30),
      ...arc(0, .30, .34, 0, 180, 26), // gancho por la cima
      const Offset(-.34, .30), const Offset(-.34, .10),
    ];

    // Tienda: techo plano + toldo que sobresale + PUERTA (la muesca central
    // es lo que la hace leerse como tienda y no como camiseta).
    const store = <Offset>[
      Offset(-.78, .60), Offset(.78, .60),   // techo
      Offset(.90, .30), Offset(.62, .30),    // toldo derecho
      Offset(.62, -.70),                     // pared derecha
      Offset(.18, -.70), Offset(.18, -.24),  // puerta (lado derecho)
      Offset(-.18, -.24), Offset(-.18, -.70),// puerta (lado izquierdo)
      Offset(-.62, -.70),                    // base izquierda
      Offset(-.62, .30), Offset(-.90, .30),  // pared + toldo izquierdo
    ];

    final heart = List<Offset>.generate(_kN, (i) {
      final a = i / _kN * _kTau;
      return Offset(
        .058 * 16 * math.pow(math.sin(a), 3).toDouble(),
        .058 *
                (13 * math.cos(a) -
                    5 * math.cos(2 * a) -
                    2 * math.cos(3 * a) -
                    math.cos(4 * a)) -
            .06,
      );
    });

    return {
      VendiOrbShape.palomilla: _resample(palomilla),
      VendiOrbShape.user: _resample(user),
      VendiOrbShape.phone: _resample(phone),
      VendiOrbShape.lock: _resample(lock),
      VendiOrbShape.store: _resample(store),
      VendiOrbShape.heart: _resample(heart),
    };
  }

  /// Re-muestrea la polilínea cerrada a N puntos equidistantes por arco,
  /// arrancando SIEMPRE en el punto más alto (ancla canónica → morphs sanos).
  static List<Offset> _resample(List<Offset> raw) {
    final pts = <Offset>[];
    for (final q in raw) {
      if (pts.isEmpty || (q - pts.last).distance > 1e-4) pts.add(q);
    }
    var top = 0;
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].dy > pts[top].dy) top = i;
    }
    final ord = [...pts.sublist(top), ...pts.sublist(0, top)];
    final lens = <double>[0];
    var per = 0.0;
    for (var i = 0; i < ord.length; i++) {
      per += (ord[(i + 1) % ord.length] - ord[i]).distance;
      lens.add(per);
    }
    var out = List.generate(_kN, (k) {
      final d = per * k / _kN;
      var i = 0;
      while (lens[i + 1] < d) {
        i++;
      }
      final a = ord[i % ord.length], b = ord[(i + 1) % ord.length];
      final t = (d - lens[i]) / ((lens[i + 1] - lens[i]) == 0 ? 1 : (lens[i + 1] - lens[i]));
      return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    }, growable: false);
    // Suavizado gaussiano circular (2 pasadas, ventana 5): redondea TODAS
    // las esquinas — bordes suaves, nunca picos (feedback del fundador).
    const w = [1.0, 4.0, 6.0, 4.0, 1.0];
    for (var pass = 0; pass < 2; pass++) {
      out = List.generate(_kN, (k) {
        var x = 0.0, y = 0.0;
        for (var d = 0; d < 5; d++) {
          final pt = out[(k + d - 2 + _kN) % _kN];
          x += pt.dx * w[d];
          y += pt.dy * w[d];
        }
        return Offset(x / 16, y / 16);
      }, growable: false);
    }
    return out;
  }

  /// Rotación + orientación del recorrido que minimizan la distancia total
  /// entre puntos homólogos — transiciones sin retorcimientos.
  static List<Offset> aligned(List<Offset> from, List<Offset> to) {
    var bestRev = false, bestOff = 0;
    var bestD = double.infinity;
    for (final rev in [false, true]) {
      final b = rev ? to.reversed.toList(growable: false) : to;
      for (var off = 0; off < _kN; off += 2) {
        var d = 0.0;
        for (var i = 0; i < _kN; i += 8) {
          final delta = from[i] - b[(i + off) % _kN];
          d += delta.dx * delta.dx + delta.dy * delta.dy;
        }
        if (d < bestD) {
          bestD = d;
          bestRev = rev;
          bestOff = off;
        }
      }
    }
    final b = bestRev ? to.reversed.toList(growable: false) : to;
    return List.generate(_kN, (i) => b[(i + bestOff) % _kN], growable: false);
  }
}
