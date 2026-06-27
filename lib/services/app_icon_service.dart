// Spec: specs/086-branding-estacional/spec.md
//
// Cambia el ícono de la app nativa según la temporada (icon_variant). Web es
// NO-OP (la PWA instalada congela su ícono — límite de Apple/Android). En móvil
// usa flutter_dynamic_icon_plus. Idempotente (solo actúa si cambió) y guardado
// en try/catch: JAMÁS rompe el arranque ni dispara el alert de iOS repetido.

import 'app_icon_service_io.dart'
    if (dart.library.html) 'app_icon_service_web.dart';

/// Aplica el ícono de la temporada [variant] si cambió respecto al último
/// aplicado. Llamar en cold-start idle (no a mitad de cobro). Nunca lanza.
Future<void> applySeasonalIcon(String? variant) =>
    applySeasonalIconImpl(variant);
