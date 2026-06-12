// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
//
// Tokens visuales del Dashboard (rediseño UI/UX 2026-06-12). SOLO
// presentación — cero lógica. Equilibrio: look moderno (limpio, sutilmente
// translúcido estilo GitHub/Apple) con contraste altísimo para usuarios 50+.
//
//  · Espaciado estricto en múltiplos de 8 (8/16/24).
//  · Texto principal #1F2937 · secundario #6B7280.
//  · Tarjetas: borde "hairline" rgba(0,0,0,0.05) + sombra muy difuminada
//    y amplia (blur 20, ~3% de opacidad) — nada de sombras pesadas.
//  · Listas agrupadas (inset grouped, estilo Ajustes de iOS): UN contenedor
//    blanco por sección, divisores internos de 1px gris clarísimo.

import 'package:flutter/material.dart';

abstract final class DashUI {
  // ── Espaciado (escala 8px) ──
  static const double s8 = 8;
  static const double s16 = 16;
  static const double s24 = 24;

  // ── Radius ──
  static const double rCard = 16;
  static const double rButton = 14;

  // ── Tipografía / contraste ──
  static const Color ink = Color(0xFF1F2937); // texto principal
  static const Color inkSoft = Color(0xFF6B7280); // subtítulos descriptivos

  /// Borde sutil 1px — rgba(0,0,0,0.05).
  static const Color hairline = Color(0x0D000000);

  /// Divisor interno de listas agrupadas — gris clarísimo.
  static const Color divider = Color(0xFFF3F4F6);

  /// Sombra muy difuminada y amplia (blur 20, 3% de opacidad).
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x08000000), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// Decoración estándar de tarjeta/grupo: blanca, radius 16, borde
  /// hairline + sombra suave. Reemplaza las sombras pesadas anteriores.
  static BoxDecoration card({double radius = rCard}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: hairline, width: 1),
        boxShadow: softShadow,
      );
}

/// Badge semántico pequeño (píldora): fondo al 12%, punto + texto fuerte.
/// Usado p. ej. para el estado "Activo" de una capacidad en el carrusel.
class DashStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const DashStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
