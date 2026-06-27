// Spec: frontend/DESIGN_SYSTEM.md (identidad de marca VendIA)
//
// Logo VendIA como COMPONENTES (no imágenes): el wordmark "Vend" + "IA" (la "IA"
// en cyan de marca, mayúscula) con la fuente de marca (Inter, equivalente a la de
// Apple), y la marca gráfica (check que asciende como flecha) en un cuadrado
// redondeado azul→cyan. Reconstruidos del board "Nueva identidad VendIA".

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wordmark "VendIA": "Vend" en [baseColor], "IA" en cyan de marca y mayúscula.
class VendiaWordmark extends StatelessWidget {
  final double fontSize;
  final Color? baseColor;

  const VendiaWordmark({super.key, this.fontSize = 28, this.baseColor});

  @override
  Widget build(BuildContext context) {
    final base = baseColor ?? AppTheme.primaryDark;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.0,
        ),
        children: [
          TextSpan(text: 'Vend', style: TextStyle(color: base)),
          const TextSpan(text: 'IA', style: TextStyle(color: AppTheme.accent)),
        ],
      ),
    );
  }
}

/// Marca gráfica: cuadrado redondeado con el check que asciende como flecha,
/// trazo en gradiente azul→cyan. [size] es el lado del cuadrado.
class VendiaMark extends StatelessWidget {
  final double size;
  final bool filledBackground;

  const VendiaMark({super.key, this.size = 48, this.filledBackground = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: filledBackground
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primaryDark, AppTheme.primary],
              )
            : null,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: CustomPaint(
        painter: _CheckArrowPainter(
          color: filledBackground ? Colors.white : AppTheme.primary,
          accent: AppTheme.accent,
        ),
      ),
    );
  }
}

/// Logo completo: marca + wordmark en fila (para headers/onboarding/login).
class VendiaLogo extends StatelessWidget {
  final double height;
  final Color? wordColor;

  const VendiaLogo({super.key, this.height = 40, this.wordColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VendiaMark(size: height),
        SizedBox(width: height * 0.28),
        VendiaWordmark(fontSize: height * 0.62, baseColor: wordColor),
      ],
    );
  }
}

class _CheckArrowPainter extends CustomPainter {
  final Color color;
  final Color accent;

  _CheckArrowPainter({required this.color, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.12;

    // Check que sube y se convierte en flecha ascendente (arriba-derecha).
    final path = Path()
      ..moveTo(w * 0.24, h * 0.52)
      ..lineTo(w * 0.43, h * 0.70) // bajada del check
      ..lineTo(w * 0.78, h * 0.26); // subida larga (flecha)

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [color, accent],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, paint);

    // Punta de flecha en el extremo superior derecho.
    final head = Path()
      ..moveTo(w * 0.78, h * 0.26)
      ..lineTo(w * 0.62, h * 0.27)
      ..moveTo(w * 0.78, h * 0.26)
      ..lineTo(w * 0.77, h * 0.42);
    final headPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    canvas.drawPath(head, headPaint);
  }

  @override
  bool shouldRepaint(_CheckArrowPainter old) =>
      old.color != color || old.accent != accent;
}
