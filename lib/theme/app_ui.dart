// Spec: specs/062-ui-highend-kit/spec.md
//
// Kit de UI de alta gama (estilo Linear/GitHub) — la REGLA visual para
// módulos nuevos y refactorizados. Solo presentación, cero lógica.
//
// Principios (ver frontend/UI_RULES.md §12):
//   · Descompresión: espaciado estricto en múltiplos de 8.
//   · Tarjetas BLANCAS puras, radius 12, sombra difusa y amplia de muy
//     baja opacidad (0px 4px 24px rgba(0,0,0,0.04)). Sin bordes pesados.
//   · Separadores casi invisibles (#F1F5F9), o mejor: whitespace.
//   · Listas agrupadas (inset grouped): UN contenedor, ítems con
//     divisor hairline, sin caja por ítem.
//   · Tipografía con contraste: títulos SemiBold #1E293B; secundario
//     14px #64748B. Sin texto redundante.
//   · Densidad moderna (decisión del fundador 2026-06-16: la prioridad
//     pasó de gerontodiseño a estándares modernos de UI/UX). Objetivos
//     táctiles ~44dp (HIG/Material), interfaz intuitiva por sí misma.

import 'dart:ui';

import 'package:flutter/material.dart';

abstract final class AppUI {
  // ── Espaciado (escala 8px) ──
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;

  static const double radius = 12;

  // ── Color / tipografía (slate) ──
  static const Color ink = Color(0xFF1E293B); // títulos
  static const Color inkSoft = Color(0xFF64748B); // secundario
  static const Color hairline = Color(0xFFF1F5F9); // divisor casi invisible
  static const Color pageBg = Color(0xFFF8FAFC); // fondo de página

  // Sombra difusa y amplia, ~4% — nada de sombras pesadas.
  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 24, offset: Offset(0, 4)),
  ];

  /// Decoración de tarjeta BLANCA pura.
  static BoxDecoration card({double r = radius}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r),
        boxShadow: shadow,
      );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: ink,
    letterSpacing: -0.2,
  );

  /// Encabezado de sección (label sobrio sobre el grupo).
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: inkSoft,
    letterSpacing: 0.2,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: ink,
  );

  static const TextStyle bodySoft = TextStyle(
    fontSize: 14,
    color: inkSoft,
    height: 1.35,
  );
}

/// Tarjeta blanca pura con sombra difusa (sin bordes pesados).
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppUI.s16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: AppUI.card(),
      child: child,
    );
  }
}

/// Lista agrupada (inset grouped, estilo Ajustes de iOS): un solo
/// contenedor blanco; los ítems se separan con un divisor hairline,
/// sin caja individual por ítem.
class InsetGroupedList extends StatelessWidget {
  final List<Widget> children;

  const InsetGroupedList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppUI.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppUI.hairline,
                indent: 64,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Badge minimalista: fondo pastel al 10% del color, sin borde, peso
/// medium 12px.
class MinimalBadge extends StatelessWidget {
  final String label;
  final Color color;

  const MinimalBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Header con glassmorphism funcional — blur 15 + blanco 65%. Úsese SOLO
/// en barras (header/bottom), nunca sobre el área de datos.
PreferredSizeWidget glassAppBar({
  required String title,
  VoidCallback? onBack,
}) {
  return AppBar(
    backgroundColor: Colors.white.withValues(alpha: 0.65),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: 0,
    leading: onBack == null
        ? null
        : IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink),
            onPressed: onBack,
          ),
    title: Text(title, style: AppUI.title),
    flexibleSpace: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: const SizedBox.expand(),
      ),
    ),
  );
}
