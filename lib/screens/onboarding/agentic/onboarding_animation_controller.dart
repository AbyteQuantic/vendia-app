// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
//
// Host de los AnimationControllers del Top Canvas (Animation Expert). NUNCA
// escribe campos de negocio — es 100% presentación; el OnboardingStepperController
// sigue siendo la única fuente de verdad. Vive atado al State del view (vsync)
// y se dispone en orden inverso a su creación.
import 'package:flutter/material.dart';

class OnboardingAnimationController {
  OnboardingAnimationController({
    required TickerProvider vsync,
    this.reduceMotion = false,
  }) {
    _stepTransition = AnimationController(
        vsync: vsync, duration: const Duration(milliseconds: 380));
    _orbit = AnimationController(
        vsync: vsync, duration: const Duration(milliseconds: 1800));
    _category = AnimationController(
        vsync: vsync, duration: const Duration(milliseconds: 520));
    _logo = AnimationController(
        vsync: vsync, duration: const Duration(milliseconds: 720));

    stepFade = CurvedAnimation(parent: _stepTransition, curve: Curves.easeInOutCubic);
    orbit = CurvedAnimation(parent: _orbit, curve: Curves.linear);
    // easeOutBack: overshoot ~1.08 y asienta — efecto de "aterrizaje".
    categoryScale = Tween(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _category, curve: Curves.easeOutBack));
    categoryOpacity = CurvedAnimation(
        parent: _category, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    // elasticOut: spring del contenedor de logo desde el centro.
    logoScale = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _logo,
        curve: reduceMotion ? Curves.easeOutBack : Curves.elasticOut));
    logoShadowOpacity = CurvedAnimation(
        parent: _logo, curve: const Interval(0.3, 1.0, curve: Curves.easeOut));

    if (reduceMotion) {
      // Reduce-motion (accesibilidad SO): salta a end-state sin tween.
      for (final c in [_stepTransition, _category, _logo]) {
        c.value = 1.0;
      }
    } else {
      _orbit.repeat();
    }
  }

  final bool reduceMotion;

  late final AnimationController _stepTransition;
  late final AnimationController _orbit;
  late final AnimationController _category;
  late final AnimationController _logo;

  late final Animation<double> stepFade;
  late final Animation<double> orbit;
  late final Animation<double> categoryScale;
  late final Animation<double> categoryOpacity;
  late final Animation<double> logoScale;
  late final Animation<double> logoShadowOpacity;

  bool get isAnimating =>
      _stepTransition.isAnimating || _category.isAnimating || _logo.isAnimating;

  /// Dispara la transición de entrada de un paso (recompensa tras validar).
  void enterStep() {
    if (reduceMotion) {
      _stepTransition.value = 1.0;
      return;
    }
    _stepTransition.forward(from: 0);
  }

  /// Reversa simétrica de la transición de paso (undo). El estado de negocio
  /// lo restaura la pila de respuestas; esto es SOLO visual.
  void reverseStep() {
    if (reduceMotion) return;
    if (_stepTransition.value > 0) _stepTransition.reverse();
  }

  /// Refleja el estado de datos en los efectos: el ícono de categoría y el
  /// spring del logo aparecen/desaparecen según haya tipo/logo. Idempotente.
  void reflect({required bool hasType, required bool hasLogo}) {
    if (reduceMotion) {
      _category.value = hasType ? 1.0 : 0.0;
      _logo.value = hasLogo ? 1.0 : 0.0;
      return;
    }
    if (hasType && _category.value == 0) {
      _category.forward(from: 0);
    } else if (!hasType && _category.value > 0) {
      _category.reverse();
    }
    if (hasLogo && _logo.value == 0) {
      _logo.forward(from: 0);
    } else if (!hasLogo && _logo.value > 0) {
      _logo.reverse();
    }
  }

  void dispose() {
    // Orden inverso a la creación (logo→category→orbit→stepTransition).
    _logo.dispose();
    _category.dispose();
    _orbit.dispose();
    _stepTransition.dispose();
  }
}
