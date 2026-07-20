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

enum VendiOrbShape {
  palomilla,
  user,
  phone,
  lock,
  store,
  heart,
  // Formas por follow-up (Adenda A: el símbolo se transforma con cada
  // pregunta — feedback fundador "sigue muy estático").
  mesa,
  casa,
  cuaderno,
  costal,
}

/// Estado anímico del orbe (Adenda A): un solo gesto a la vez.
/// - [asking]: inclinación sutil sostenida + pulso de invitación cada ~5 s.
/// - [thinking]: el destello del contorno acelera y la respiración se contrae.
/// - [explaining]: un barrido único del destello + asentimiento hacia el
///   contenido, una sola vez por mensaje.
/// - [settled]: pulso único de cierre y el destello se apaga (quietud = listo).
/// Con reduce-motion la FORMA porta el estado y los gestos se omiten.
enum VendiOrbMood { idle, asking, thinking, explaining, settled }

const int _kN = 160;
const double _kTau = math.pi * 2;

/// Solo para verificación visual en tests: expone los puntos re-muestreados
/// de una forma (renderizarlos fuera de Flutter antes de embarcar cambios).
@visibleForTesting
List<Offset> debugVendiShapePoints(VendiOrbShape s) => _VendiShapes.of(s);

class VendiOrb extends StatefulWidget {
  const VendiOrb({
    super.key,
    required this.shape,
    this.size = 200,
    this.mood = VendiOrbMood.idle,
    this.beat = 0,
  });

  final VendiOrbShape shape;
  final double size;
  final VendiOrbMood mood;

  /// Latido por mensaje: cada vez que cambia, el orbe puntúa con un barrido
  /// rápido del destello + un pulso corto — aunque la forma no cambie.
  final int beat;

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

  // Fundido entre parámetros del mood anterior y el actual (alpha/velocidad
  // del destello, centro de respiración, inclinación).
  late final AnimationController _moodCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: 1,
  );

  Ticker? _life;
  final ValueNotifier<double> _t = ValueNotifier(0); // segundos de vida
  // Fase acumulada del destello viajero: acumular (dt / vuelta) en vez de
  // derivarla del reloj mantiene la posición continua cuando la velocidad
  // cambia entre moods (sin saltos visibles).
  final ValueNotifier<double> _glowPhase = ValueNotifier(0);
  double _lastLifeT = 0;

  VendiOrbMood _prevMood = VendiOrbMood.idle;
  double _moodStartT = 0; // _t.value al entrar al mood (gestos one-shot)
  double _phaseAtMood = 0; // fase del destello al entrar (barrido único)

  late List<Offset> _from;
  late List<Offset> _to;

  @override
  void initState() {
    super.initState();
    _from = List.of(_VendiShapes.of(widget.shape));
    _to = List.of(_from);
    _morph.value = 1;
    _prevMood = widget.mood;
  }

  double _phaseAtBeat = 0;
  double _beatStartT = 0;

  double _glowLapSeconds() {
    // Barrido de puntuación por mensaje nuevo: una vuelta rápida.
    if ((_glowPhase.value - _phaseAtBeat) < 1.0 && _beatStartT > 0) {
      return 1.4;
    }
    switch (widget.mood) {
      case VendiOrbMood.thinking:
        return 2.2; // se concentra
      case VendiOrbMood.explaining:
        // Barrido de presentación: UNA vuelta rápida y vuelve al reposo.
        return (_glowPhase.value - _phaseAtMood) < 1.0 ? 1.4 : 6.0;
      default:
        return 6.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduce && _life == null) {
      _life = createTicker((elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        _glowPhase.value += (t - _lastLifeT) / _glowLapSeconds();
        _lastLifeT = t;
        _t.value = t;
      })
        ..start();
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
    if (old.beat != widget.beat) {
      _beatStartT = _t.value;
      _phaseAtBeat = _glowPhase.value;
    }
    if (old.mood != widget.mood) {
      _prevMood = old.mood;
      _moodStartT = _t.value;
      _phaseAtMood = _glowPhase.value;
      // Entrada al gesto de pregunta más pausada; el cierre se asienta lento.
      _moodCtrl.duration = switch (widget.mood) {
        VendiOrbMood.asking => const Duration(milliseconds: 700),
        VendiOrbMood.settled => const Duration(milliseconds: 800),
        _ => const Duration(milliseconds: 450),
      };
      _moodCtrl.forward(from: 0);
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
    _moodCtrl.dispose();
    _t.dispose();
    _glowPhase.dispose();
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
          glowPhase: _glowPhase,
          isIcon: widget.shape != VendiOrbShape.palomilla,
          mood: widget.mood,
          prevMood: _prevMood,
          moodAnim: _moodCtrl,
          moodStartT: _moodStartT,
          beatStartT: _beatStartT,
          repaint: Listenable.merge([_morph, _t, _moodCtrl]),
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
    required this.glowPhase,
    required this.isIcon,
    required this.mood,
    required this.prevMood,
    required this.moodAnim,
    required this.moodStartT,
    required this.beatStartT,
    required super.repaint,
  });

  final List<Offset> from;
  final List<Offset> to;
  final Animation<double> morph;
  final ValueNotifier<double> time;
  final ValueNotifier<double> glowPhase;
  final bool isIcon;
  final VendiOrbMood mood;
  final VendiOrbMood prevMood;
  final Animation<double> moodAnim;
  final double moodStartT;
  final double beatStartT;

  // Parámetros por mood; el painter funde prev→actual con moodAnim.
  static double _glowAlphaFor(VendiOrbMood m) => switch (m) {
        VendiOrbMood.thinking => .70,
        VendiOrbMood.settled => .15,
        _ => .55,
      };

  static double _breatheCenterFor(VendiOrbMood m) =>
      m == VendiOrbMood.thinking ? -.03 : 0;

  static double _tiltFor(VendiOrbMood m) => m == VendiOrbMood.asking ? 1 : 0;

  // Piensa = el destello "escanea" un tramo más largo del contorno.
  static double _glowFracFor(VendiOrbMood m) =>
      m == VendiOrbMood.thinking ? .32 : .20;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(size.width, size.height) * .40;
    final k = Curves.easeInOutCubic.transform(morph.value);
    final now = time.value;
    // moodT: segundos dentro del mood actual (0 fijo con reduce-motion —
    // los gestos one-shot y pulsos se quedan quietos, la forma comunica).
    final moodT = math.max(0.0, now - moodStartT);
    final blend = Curves.easeInOutSine.transform(moodAnim.value);
    double mix(double a, double b) => a + (b - a) * blend;

    // Vida: la palomilla respira amplio; los íconos definidos apenas laten.
    final amp = isIcon ? .007 : .016;
    final settledMorph = morph.isCompleted || morph.value == 1;
    final center = mix(_breatheCenterFor(prevMood), _breatheCenterFor(mood));
    final breathe = center + amp * 1.6 * math.sin(now / 1.05);
    // Los ÍCONOS no ondulan el contorno (deformaba la silueta — feedback
    // fundador): su vida es la respiración uniforme + el destello. Solo la
    // palomilla, que es abstracta, ondula.
    final wobAmp = isIcon
        ? 0.0
        : (settledMorph ? amp : 0) + (mood == VendiOrbMood.thinking ? .015 : 0);

    // Gestos one-shot (un solo canal de señal a la vez, Adenda A):
    // pregunta = pulso de invitación; cierre = pulso único de asentamiento.
    var extraScale = 0.0;
    if (mood == VendiOrbMood.asking && moodT > 0) {
      final tp = moodT % 5.0;
      if (tp < 1.2) extraScale += .02 * math.sin(math.pi * tp / 1.2);
    }
    if (mood == VendiOrbMood.settled && moodT > 0 && moodT < .9) {
      extraScale += .05 * math.sin(math.pi * moodT / .9);
    }
    // Latido por mensaje nuevo: pulso corto aunque la forma no cambie.
    final beatT = now - beatStartT;
    if (beatStartT > 0 && beatT > 0 && beatT < .7) {
      extraScale += .03 * math.sin(math.pi * beatT / .7);
    }
    // Explicar = asentimiento hacia el contenido (baja 6dp y regresa).
    var nod = 0.0;
    if (mood == VendiOrbMood.explaining && moodT > 0) {
      if (moodT < .6) {
        nod = 6 * Curves.easeOutCubic.transform(moodT / .6);
      } else if (moodT < 1.2) {
        nod = 6 * (1 - Curves.easeInOut.transform((moodT - .6) / .6));
      }
    }
    // Pregunta = leve inclinación de cabeza sostenida mientras espera.
    final tilt = mix(_tiltFor(prevMood), _tiltFor(mood)) * 2.5 * math.pi / 180;

    canvas.save();
    canvas.translate(cx, cy + nod);
    if (tilt != 0) canvas.rotate(tilt);
    canvas.translate(-cx, -cy);

    // Ondulación de BAJA frecuencia: 2 ondas suaves recorren el contorno.
    final p = List<Offset>.generate(_kN, (j) {
      final a = from[j], b = to[j];
      final x = a.dx + (b.dx - a.dx) * k;
      final y = a.dy + (b.dy - a.dy) * k;
      final s = 1 +
          breathe +
          extraScale +
          wobAmp * math.sin(now / 1.1 + (j / _kN) * _kTau * 2);
      // y matemática (arriba positivo) → canvas (abajo positivo)
      return Offset(cx + x * s * r, cy - y * s * r);
    }, growable: false);

    // Curva CERRADA y SUAVE: cuadráticas entre puntos medios (sin facetas).
    final path = Path();
    Offset mid(Offset a, Offset b) =>
        Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
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
    final shader = gradient
        .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));

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
    // recorre la forma — la señal de que Vendi está viva. La velocidad y el
    // brillo los gobierna el mood (pensar acelera; el cierre lo apaga).
    final glowAlpha = mix(_glowAlphaFor(prevMood), _glowAlphaFor(mood));
    final glowLen =
        (_kN * mix(_glowFracFor(prevMood), _glowFracFor(mood))).round();
    final start = (glowPhase.value % 1.0 * _kN).floor();
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
      ..color = AppTheme.accent.withValues(alpha: glowAlpha);
    canvas.drawPath(glowPath, glow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.from != from ||
      old.to != to ||
      old.mood != mood ||
      old.prevMood != prevMood;
}

// ── Formas: anclas limpias → re-muestreo por arco (idéntico al prototipo) ───
class _VendiShapes {
  static final Map<VendiOrbShape, List<Offset>> _cache = _build();

  static List<Offset> of(VendiOrbShape s) => _cache[s]!;

  static Map<VendiOrbShape, List<Offset>> _build() {
    List<Offset> arc(
        double cx, double cy, double r, double a0deg, double a1deg, int steps) {
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
      Offset(-.60, .26), // tope del brazo corto
      Offset(-.16, -.16), // codo interior
      Offset(.58, .64), // subida del brazo largo
      Offset(.84, .40), // punta exterior
      Offset(-.17, -.62), // codo exterior (vértice del chulo)
      Offset(-.84, .02), // punta del brazo corto
    ];

    // Silueta de usuario ANALÍTICA (feedback fundador 2026-07-20: "sigue muy
    // deforme"): cabeza = círculo denso; hombros = Béziers simétricos con
    // tangentes continuas; base casi plana con esquinas redondeadas. Se
    // verificó el render (pipeline replicado) antes de embarcar.
    List<Offset> bez(Offset p0, Offset p1, Offset p2, Offset p3, int steps) {
      return List.generate(steps + 1, (i) {
        final t = i / steps, u = 1 - t;
        return Offset(
          u * u * u * p0.dx +
              3 * u * u * t * p1.dx +
              3 * u * t * t * p2.dx +
              t * t * t * p3.dx,
          u * u * u * p0.dy +
              3 * u * u * t * p1.dy +
              3 * u * t * t * p2.dy +
              t * t * t * p3.dy,
        );
      });
    }

    final user = <Offset>[
      ...arc(0, .40, .30, 245, -65, 64), // cabeza — círculo de verdad
      ...bez(const Offset(.127, .128), const Offset(.30, .02),
          const Offset(.56, -.10), const Offset(.62, -.34), 24),
      ...bez(const Offset(.62, -.34), const Offset(.64, -.50),
          const Offset(.62, -.62), const Offset(.48, -.64), 12),
      const Offset(.30, -.66), const Offset(0, -.665), const Offset(-.30, -.66),
      ...bez(const Offset(-.48, -.64), const Offset(-.62, -.62),
          const Offset(-.64, -.50), const Offset(-.62, -.34), 12),
      ...bez(const Offset(-.62, -.34), const Offset(-.56, -.10),
          const Offset(-.30, .02), const Offset(-.127, .128), 24),
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
      Offset(-.78, .60), Offset(.78, .60), // techo
      Offset(.90, .30), Offset(.62, .30), // toldo derecho
      Offset(.62, -.70), // pared derecha
      Offset(.18, -.70), Offset(.18, -.24), // puerta (lado derecho)
      Offset(-.18, -.24), Offset(-.18, -.70), // puerta (lado izquierdo)
      Offset(-.62, -.70), // base izquierda
      Offset(-.62, .30), Offset(-.90, .30), // pared + toldo izquierdo
    ];

    // Formas por follow-up (Adenda A) — verificadas con render del pipeline
    // antes de embarcar (scratchpad/orbshape.py).
    // mesa: tablero + dos patas (muesca inferior central).
    const mesa = <Offset>[
      Offset(-.85, .30), Offset(.85, .30), Offset(.85, .06), Offset(.55, .06),
      Offset(.55, -.60), Offset(.30, -.60), Offset(.30, .06), Offset(-.30, .06),
      Offset(-.30, -.60), Offset(-.55, -.60), Offset(-.55, .06),
      Offset(-.85, .06),
    ];

    // casa: techo triangular + paredes + puerta.
    const casa = <Offset>[
      Offset(0, .80), Offset(.75, .25), Offset(.55, .25), Offset(.55, -.60),
      Offset(.18, -.60), Offset(.18, -.15), Offset(-.18, -.15),
      Offset(-.18, -.60), Offset(-.55, -.60), Offset(-.55, .25),
      Offset(-.75, .25),
    ];

    // cuaderno: libreta con argollas arriba — el cuaderno de fiados.
    final cuaderno = <Offset>[
      const Offset(-.62, .48),
      for (var i = 0; i < 4; i++) ...arc(-.45 + i * .30, .48, .10, 180, 0, 10),
      const Offset(.62, .48), const Offset(.62, -.62), const Offset(-.62, -.62),
    ];

    // costal: saco amarrado — tela anudada + hombros caídos + base ancha.
    final costal = <Offset>[
      const Offset(-.26, .52), const Offset(-.14, .66), const Offset(0, .58),
      const Offset(.14, .66), const Offset(.26, .52), const Offset(.14, .38),
      ...bez(const Offset(.14, .38), const Offset(.60, .24),
          const Offset(.70, -.34), const Offset(.40, -.60), 20),
      const Offset(0, -.64),
      ...bez(const Offset(-.40, -.60), const Offset(-.70, -.34),
          const Offset(-.60, .24), const Offset(-.14, .38), 20),
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
      // La silueta ya es suave por construcción: 1 sola pasada conserva la
      // definición (2 pasadas le derriten el cuello).
      VendiOrbShape.user: _resample(user, passes: 1),
      VendiOrbShape.phone: _resample(phone),
      VendiOrbShape.lock: _resample(lock),
      VendiOrbShape.store: _resample(store),
      VendiOrbShape.heart: _resample(heart),
      VendiOrbShape.mesa: _resample(mesa, passes: 1),
      VendiOrbShape.casa: _resample(casa, passes: 1),
      VendiOrbShape.cuaderno: _resample(cuaderno, passes: 1),
      VendiOrbShape.costal: _resample(costal, passes: 1),
    };
  }

  /// Re-muestrea la polilínea cerrada a N puntos equidistantes por arco,
  /// arrancando SIEMPRE en el punto más alto (ancla canónica → morphs sanos).
  static List<Offset> _resample(List<Offset> raw, {int passes = 2}) {
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
      final t = (d - lens[i]) /
          ((lens[i + 1] - lens[i]) == 0 ? 1 : (lens[i + 1] - lens[i]));
      return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    }, growable: false);
    // Suavizado gaussiano circular (2 pasadas, ventana 5): redondea TODAS
    // las esquinas — bordes suaves, nunca picos (feedback del fundador).
    const w = [1.0, 4.0, 6.0, 4.0, 1.0];
    for (var pass = 0; pass < passes; pass++) {
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
