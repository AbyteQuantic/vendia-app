// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
//
// Top Canvas (Animation Expert): lienzo limpio que "construye" la identidad del
// negocio a medida que se responde. Todo Transform/Opacity (capa de compositor,
// cero relayout), bajo RepaintBoundary. Lee el OnboardingStepperController
// (estado) + el OnboardingAnimationController (animaciones).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'onboarding_animation_controller.dart';
import 'onboarding_cards.dart' show kBusinessTypeLabels;

const Map<String, IconData> _typeIcons = {
  'tienda_barrio': Icons.storefront_rounded,
  'minimercado': Icons.local_grocery_store_rounded,
  'deposito_construccion': Icons.handyman_rounded,
  'restaurante': Icons.restaurant_rounded,
  'comidas_rapidas': Icons.lunch_dining_rounded,
  'bar': Icons.local_bar_rounded,
  'manufactura': Icons.precision_manufacturing_rounded,
  'reparacion_muebles': Icons.chair_rounded,
  'emprendimiento_general': Icons.lightbulb_rounded,
  'academias_instituciones': Icons.school_rounded,
};

class PreviewCanvasWidget extends StatelessWidget {
  const PreviewCanvasWidget({
    super.key,
    required this.anim,
    required this.businessName,
    required this.ownerName,
    required this.phone,
    required this.businessType,
    required this.logoUrl,
    this.compact = false,
    this.backgroundColor = const Color(0xFFFAFAFA),
  });

  final OnboardingAnimationController anim;
  final String businessName;
  final String ownerName;
  final String phone;
  final String businessType;
  final String logoUrl;
  final bool compact; // teclado abierto → versión mini
  /// Fondo del canvas. Transparente cuando hay un video de fondo detrás.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        color: backgroundColor,
        width: double.infinity,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: compact ? 8 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _logo(),
                const SizedBox(height: 16),
                _name(),
                const SizedBox(height: 10),
                _category(),
                if (!compact) ...[
                  const SizedBox(height: 22),
                  _orbitals(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Contenedor de logo con spring (elasticOut). Sombra etérea estática.
  Widget _logo() {
    final size = compact ? 64.0 : 96.0;
    return AnimatedBuilder(
      animation: anim.logoScale,
      builder: (_, child) {
        final hasLogo = logoUrl.isNotEmpty;
        final scale = hasLogo ? anim.logoScale.value.clamp(0.0, 1.2) : 1.0;
        return Transform.scale(
          scale: hasLogo ? scale : 1.0,
          child: Opacity(
            opacity: hasLogo
                ? anim.logoShadowOpacity.value.clamp(0.0, 1.0)
                : 1.0,
            child: child,
          ),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.6)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x05000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: logoUrl.isNotEmpty
            ? Image.network(logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _logoPlaceholder())
            : _logoPlaceholder(),
      ),
    );
  }

  Widget _logoPlaceholder() => Center(
        child: Icon(Icons.add_business_rounded,
            size: compact ? 28 : 40,
            color: AppTheme.borderColor),
      );

  Widget _name() {
    final text = businessName.isNotEmpty ? businessName : 'Su negocio';
    return AnimatedOpacity(
      opacity: businessName.isNotEmpty ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 300),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 18 : 22,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  // Ícono de categoría: fundido + escala con easeOutBack.
  Widget _category() {
    if (businessType.isEmpty) {
      return const SizedBox(height: 28);
    }
    final icon = _typeIcons[businessType] ?? Icons.category_rounded;
    final label = kBusinessTypeLabels[businessType] ?? businessType;
    return AnimatedBuilder(
      animation: anim.categoryScale,
      builder: (_, child) => Opacity(
        opacity: anim.categoryOpacity.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: anim.categoryScale.value.clamp(0.0, 1.2),
          child: child,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // Chips orbitales con flotación senoidal de baja amplitud.
  Widget _orbitals() {
    final chips = <Widget>[
      if (ownerName.isNotEmpty) _orbitalChip(Icons.person_rounded, ownerName, 0),
      if (phone.isNotEmpty) _orbitalChip(Icons.phone_rounded, phone, 1),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: chips,
    );
  }

  Widget _orbitalChip(IconData icon, String text, int index) {
    return AnimatedBuilder(
      animation: anim.orbit,
      builder: (_, child) {
        // Flotación ±3dp desfasada por índice (compositor, no relayout).
        final dy = math.sin((anim.orbit.value * 2 * math.pi) + index) * 3.0;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.6)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x05000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}
