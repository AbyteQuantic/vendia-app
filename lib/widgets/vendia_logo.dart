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

/// Marca gráfica VendIA: el ícono oficial (smartphone + flecha de crecimiento,
/// gradiente azul→cyan) en un cuadrado redondeado. Usa el MISMO asset que el
/// ícono de la app para una identidad consistente. [size] es el lado.
class VendiaMark extends StatelessWidget {
  final double size;

  const VendiaMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/images/vendia_icon_1024.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
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
