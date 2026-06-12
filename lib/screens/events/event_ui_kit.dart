// Spec: specs/042-modulo-eventos/spec.md
//
// Sistema de diseño del módulo de Eventos (refactor UI/UX 2026-06-12).
// SOLO presentación — cero lógica de negocio. Reglas:
//
//  · Espaciado en múltiplos de 8 (8/16/24/32).
//  · Radius unificado: tarjetas 16 · botones 12 · badges píldora.
//  · Tarjetas SIN bordes duros: sombra suave difuminada o fondo #F8F9FA.
//  · Tipografía: títulos/métricas w700 #111827; secundario #6B7280.
//  · 3 niveles de botón:
//      Primary   → fondo sólido, texto blanco, sin borde.
//      Secondary → tinte 10% del color, texto del color, sin borde.
//      Tertiary  → solo texto, peso medium.
//  · Badges: píldora con fondo semántico al 12% y texto fuerte, sin íconos.

import 'package:flutter/material.dart';

abstract final class EventUI {
  // ── Espaciado (escala 8px) ──
  static const double s8 = 8;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;

  // ── Radius unificado ──
  static const double rCard = 16;
  static const double rButton = 12;

  // ── Tipografía / contraste ──
  static const Color ink = Color(0xFF111827); // texto principal
  static const Color inkSoft = Color(0xFF6B7280); // texto secundario
  static const Color surface = Color(0xFFF8F9FA); // fondo sutil de tarjeta

  // ── Semánticos del módulo ──
  static const Color accent = Color(0xFF0EA5E9); // cian de Eventos
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color whatsapp = Color(0xFF25D366);

  /// Sombra suave y difuminada — reemplaza los bordes de alto contraste.
  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x14111827), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static TextStyle title([double size = 17]) => TextStyle(
      fontSize: size, fontWeight: FontWeight.w700, color: ink, height: 1.25);

  static TextStyle body([double size = 14]) =>
      TextStyle(fontSize: size, color: inkSoft, height: 1.4);

  static TextStyle value([double size = 15]) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: ink);
}

/// Tarjeta del módulo: blanca, radius 16, sombra suave, SIN borde.
class EventCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Gradient? gradient;

  const EventCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(EventUI.rCard),
        boxShadow: EventUI.shadow,
      ),
      child: child,
    );
  }
}

/// Encabezado de sección dentro de una tarjeta: ícono + título w700 y
/// subtítulo opcional en gris medio.
class EventSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;

  const EventSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color = EventUI.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: EventUI.s8),
            Expanded(child: Text(title, style: EventUI.title(16))),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: EventUI.body(13.5)),
        ],
      ],
    );
  }
}

/// Primary Action — fondo sólido, texto blanco, sin borde.
class EventPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool busy;
  final double height;

  const EventPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = EventUI.accent,
    this.busy = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EventUI.rButton)),
          textStyle:
              const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white))
            : (icon != null ? Icon(icon, size: 20) : const SizedBox.shrink()),
        // FittedBox: en 360dp (o con fuente XL del sistema) el label se
        // encoge en vez de desbordar — nunca un RenderFlex overflow.
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

/// Secondary Action — tinte 10% del color, texto del color, sin borde.
class EventSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool busy;
  final double height;

  const EventSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = EventUI.accent,
    this.busy = false,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.10),
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EventUI.rButton)),
          textStyle:
              const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : (icon != null ? Icon(icon, size: 19) : const SizedBox.shrink()),
        // Igual que en EventPrimaryButton: el label se encoge, no desborda.
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

/// Tertiary/Text Action — solo texto en el color primario, peso medium.
class EventTertiaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;

  const EventTertiaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = EventUI.accent,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: EventUI.s8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
      label: Text(label),
    );
  }
}

/// Badge píldora con color semántico: fondo al 12%, texto fuerte, sin ícono.
class EventBadge extends StatelessWidget {
  final String label;
  final Color color;

  const EventBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Fila de detalle (Tipo · Fecha · Dirección…): ícono alineado a la
/// izquierda, etiqueta gris medio y valor casi negro. Sin divisores duros —
/// la separación es solo espacio.
class EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const EventInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: EventUI.inkSoft),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(label, style: EventUI.body(13.5)),
        ),
        const SizedBox(width: EventUI.s8),
        Expanded(child: Text(value, style: EventUI.value())),
      ],
    );
  }
}
