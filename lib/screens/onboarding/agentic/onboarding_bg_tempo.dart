// Spec: specs/048-onboarding-video-bg/spec.md
//
// Mapea el ESTADO del onboarding a la velocidad del video de fondo (frames/seg).
// Regla pedida:
//   - el usuario digita            → LENTO (no distrae mientras escribe),
//   - esperando su input (IA ya respondió) → LENTO-suave,
//   - "pensando" / persistiendo dato / IA procesando → se ACELERA un poco,
//   - cuando responde y volvemos a esperar input → baja de nuevo.
// El "busy" (IA/persistencia) manda sobre "typing".

enum OnboardingBgTempo { typing, idle, busy }

/// Velocidad de avance del sprite (frames por segundo) para cada tempo.
/// Valores BAJOS a propósito: el fondo es ambiental, no debe distraer. El
/// cross-fade del reproductor suaviza el movimiento aun a estas velocidades.
double bgFpsForTempo(OnboardingBgTempo t) {
  switch (t) {
    case OnboardingBgTempo.typing:
      return 1.5; // el más lento: el tendero está escribiendo
    case OnboardingBgTempo.idle:
      return 2.5; // calma: esperando el siguiente dato
    case OnboardingBgTempo.busy:
      return 6.0; // IA procesando / guardando / pensando
  }
}

/// Resuelve el tempo a partir de las señales del view.
/// [busy] = IA procesando, submit en curso o persistiendo.
/// [typing] = el usuario está escribiendo en el campo de texto.
OnboardingBgTempo resolveBgTempo({required bool busy, required bool typing}) {
  if (busy) return OnboardingBgTempo.busy;
  if (typing) return OnboardingBgTempo.typing;
  return OnboardingBgTempo.idle;
}
