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

import 'app_theme.dart';

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

  // ── Densidad "SaaS Professional" (Spec 065 — Recipe Studio) ──
  /// Borde sobrio de 1px para tablas/paneles de alta densidad (estilo ERP).
  static const Color border = Color(0xFFE2E8F0);

  /// Radio pequeño (6px) para contenedores densos — más "industrial" que el 12.
  static const double radiusSm = 6;

  /// Tarjeta blanca con BORDE de 1px (no sombra): la densidad pro del Studio.
  static BoxDecoration borderedCard({double r = radiusSm}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: border, width: 1),
      );

  /// Cifras tabulares: alinea los números en columnas de costo.
  static const TextStyle tabular = TextStyle(
    fontSize: 14,
    color: ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle tabularStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Variantes del botón estándar del design system.
enum AppButtonVariant { primary, secondary, danger }

/// AppButton — botón ESTÁNDAR del design system (regla de oro). Tamaño y
/// tipografía consistentes con el kit (alto 50, radio 12, texto 16 w600,
/// una sola línea con ellipsis — nunca se parte). Úselo SIEMPRE en lugar de
/// ElevatedButton/OutlinedButton crudos (cuyo theme legacy de 22px/64dp parte
/// el texto en pantallas estrechas).
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    const brand = AppTheme.primary;
    const danger = AppTheme.error;
    final Color fg = switch (variant) {
      AppButtonVariant.primary => Colors.white,
      AppButtonVariant.secondary => brand,
      AppButtonVariant.danger => Colors.white,
    };
    final Color? bg = switch (variant) {
      AppButtonVariant.primary => brand,
      AppButtonVariant.secondary => null,
      AppButtonVariant.danger => danger,
    };
    final label0 = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
    );
    final child = icon == null
        ? label0
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: AppUI.s8),
              Flexible(child: label0),
            ],
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppUI.radius),
    );
    final btn = variant == AppButtonVariant.secondary
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: brand,
              minimumSize: const Size(0, 50),
              shape: shape,
              side: BorderSide(color: brand.withValues(alpha: 0.5), width: 1.5),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: child,
          )
        : FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              minimumSize: const Size(0, 50),
              shape: shape,
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: child,
          );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Botón de acción secundaria (Ghost): ícono + texto, sin relleno de color.
/// Reemplaza los botones gigantes de color que rompen la densidad pro.
class GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  const GhostButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppUI.ink;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: c),
      label: Text(label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c)),
      style: TextButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: AppUI.s8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          side: const BorderSide(color: AppUI.border),
        ),
      ),
    );
  }
}

/// Card de resumen con glassmorphism real (blur + blanco translúcido + borde
/// claro). Para el resumen de costeo del Studio, que flota sobre el contenido.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppUI.s16),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppUI.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppUI.radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            boxShadow: AppUI.shadow,
          ),
          child: child,
        ),
      ),
    );
  }
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
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: Colors.white.withValues(alpha: 0.65),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: 0,
    actions: actions,
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
