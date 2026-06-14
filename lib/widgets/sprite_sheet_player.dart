// Spec: specs/048-onboarding-video-bg/spec.md
//
// Reproductor de una "película" empaquetada como sprite sheet (un solo WebP con
// los fotogramas en mosaico). Reemplaza un video MP4 pesado: el asset es liviano
// y el avance de fotograma se controla por código, así la VELOCIDAD reacciona al
// estado de la app (typing lento / IA rápido). Usa BoxFit.cover → llena desktop,
// tablet o mobile SIN deformar la relación de aspecto.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;

class SpriteSheetPlayer extends StatefulWidget {
  const SpriteSheetPlayer({
    super.key,
    required this.asset,
    required this.columns,
    required this.rows,
    required this.frameCount,
    required this.targetFps,
    this.pingPong = true,
    this.fit = BoxFit.cover,
    this.reduceMotion = false,
    this.fpsLerpPerSecond = 8.0,
    this.imageLoader,
  });

  final String asset;
  final int columns;
  final int rows;
  final int frameCount;

  /// Velocidad objetivo (frames/seg). Puede cambiar en caliente; el reproductor
  /// la interpola suave para que el cambio de ritmo no sea brusco.
  final double targetFps;
  final bool pingPong;
  final BoxFit fit;

  /// Accesibilidad: si el SO pide reducir movimiento, se muestra un fotograma
  /// fijo (sin Ticker).
  final bool reduceMotion;

  /// Cuántos fps/seg puede cambiar la velocidad actual hacia [targetFps].
  final double fpsLerpPerSecond;

  /// Inyectable en tests (evita depender de un asset real).
  final Future<ui.Image> Function(String asset)? imageLoader;

  @override
  State<SpriteSheetPlayer> createState() => _SpriteSheetPlayerState();
}

class _SpriteSheetPlayerState extends State<SpriteSheetPlayer>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _pos = 0; // posición continua en fotogramas
  double _fps = 0; // fps actual (se acerca a targetFps por lerp)
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _fps = widget.reduceMotion ? 0 : widget.targetFps;
    _load();
  }

  Future<void> _load() async {
    try {
      final loader = widget.imageLoader ?? _defaultLoader;
      final img = await loader(widget.asset);
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() => _image = img);
      if (!widget.reduceMotion) {
        _ticker = createTicker(_tick)..start();
      }
    } catch (_) {
      // Sin fondo si la carga falla — el onboarding sigue funcionando.
    }
  }

  static Future<ui.Image> _defaultLoader(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.25) return; // ignora saltos grandes (app en background)

    // Acerca la velocidad actual al objetivo de forma suave.
    final target = widget.targetFps;
    final step = widget.fpsLerpPerSecond * dt;
    if ((_fps - target).abs() <= step) {
      _fps = target;
    } else {
      _fps += target > _fps ? step : -step;
    }

    _pos += _fps * dt;
    _frame.value = frameIndexFor(_pos, widget.frameCount, widget.pingPong);
  }

  @override
  void didUpdateWidget(covariant SpriteSheetPlayer old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion && _ticker != null) {
      _ticker!
        ..stop()
        ..dispose();
      _ticker = null;
    } else if (!widget.reduceMotion && _ticker == null && _image != null) {
      _last = Duration.zero;
      _ticker = createTicker(_tick)..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frame.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpritePainter(
          image: img,
          columns: widget.columns,
          rows: widget.rows,
          frame: _frame,
          fit: widget.fit,
        ),
      ),
    );
  }
}

/// Mapea una posición continua a un índice de fotograma. En ping-pong el índice
/// va 0→N-1→1 (sin corte al reiniciar el loop).
@visibleForTesting
int frameIndexFor(double pos, int frameCount, bool pingPong) {
  if (frameCount <= 1) return 0;
  if (!pingPong) return pos.floor() % frameCount;
  final period = 2 * (frameCount - 1);
  final t = pos % period;
  final i = t.floor();
  return i < frameCount ? i : period - i;
}

class _SpritePainter extends CustomPainter {
  _SpritePainter({
    required this.image,
    required this.columns,
    required this.rows,
    required this.frame,
    required this.fit,
  }) : super(repaint: frame);

  final ui.Image image;
  final int columns;
  final int rows;
  final ValueListenable<int> frame;
  final BoxFit fit;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final fw = image.width / columns;
    final fh = image.height / rows;
    final idx = frame.value.clamp(0, columns * rows - 1);
    final col = idx % columns;
    final row = idx ~/ columns;
    final src = Rect.fromLTWH(col * fw, row * fh, fw, fh);

    // cover: escala el fotograma para CUBRIR el área y recorta lo que sobra,
    // centrado — preserva la relación de aspecto en cualquier pantalla.
    final scale = fit == BoxFit.contain
        ? math.min(size.width / fw, size.height / fh)
        : math.max(size.width / fw, size.height / fh);
    final dw = fw * scale, dh = fh * scale;
    final dst =
        Rect.fromLTWH((size.width - dw) / 2, (size.height - dh) / 2, dw, dh);
    canvas.drawImageRect(image, src, dst, _paint);
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.image != image ||
      old.columns != columns ||
      old.rows != rows ||
      old.fit != fit;
}
