import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Silent Panic Button - discrete security widget for robbery situations.
///
/// Activates after a 3-second long press. Designed to be invisible to
/// attackers: no loud sounds, no large text, no visible alerts.
///
/// Drop into any `AppBar.actions` list.
class PanicButton extends StatefulWidget {
  final VoidCallback? onPanicTriggered;

  const PanicButton({super.key, this.onPanicTriggered});

  @override
  State<PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<PanicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isHolding = false;
  bool _triggered = false;
  OverlayEntry? _overlayEntry;

  static const _idleIconColor = Color(0xFF6B7280);
  static const _activeColor = Color(0xFFDC2626);
  static const _bgColor = Color(0x158B0000);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isHolding) {
        _onPanicComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Gesture handlers
  // ---------------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails _) {
    if (_triggered) return;
    setState(() => _isHolding = true);
    _controller.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _cancelHold();
  }

  void _onLongPressCancel() {
    _cancelHold();
  }

  void _cancelHold() {
    if (!_isHolding) return;
    setState(() => _isHolding = false);
    if (!_triggered) {
      _controller.reset();
    }
  }

  // ---------------------------------------------------------------------------
  // Panic sequence
  // ---------------------------------------------------------------------------

  Future<void> _onPanicComplete() async {
    setState(() {
      _isHolding = false;
      _triggered = true;
    });

    // Red screen flash via OverlayEntry
    _showRedFlash();

    // Heavy haptic vibration x3
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();

    // Notify caller
    widget.onPanicTriggered?.call();

    // Return to idle after 5 seconds
    await Future<void>.delayed(const Duration(seconds: 5));
    if (mounted) {
      setState(() => _triggered = false);
      _controller.reset();
    }
  }

  void _showRedFlash() {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Container(color: _activeColor),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Bot\u00f3n de seguridad. Mantenga presionado 3 segundos para activar alerta silenciosa',
      button: true,
      child: GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: _onLongPressCancel,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            final iconColor =
                _triggered || (_isHolding && progress > 0)
                    ? Color.lerp(_idleIconColor, _activeColor, progress) ??
                        _idleIconColor
                    : _idleIconColor;

            return SizedBox(
              width: 36,
              height: 36,
              child: CustomPaint(
                painter: _ProgressRingPainter(
                  progress: _isHolding ? progress : (_triggered ? 1.0 : 0.0),
                  color: _activeColor,
                ),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      size: 20,
                      color: _triggered ? _activeColor : iconColor,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Progress ring painter
// -----------------------------------------------------------------------------

class _ProgressRingPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color color;

  _ProgressRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -pi / 2, 2 * pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) => old.progress != progress;
}
