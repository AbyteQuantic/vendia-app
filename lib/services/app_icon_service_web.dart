// Spec: specs/086-branding-estacional/spec.md
//
// Impl WEB: NO-OP. El ícono de una PWA instalada queda congelado por el SO al
// instalarse (iOS Add-to-Home snapshot; Chrome cachea el manifest). Lo que sí
// cambia en web por deploy: favicon, theme-color, manifest (solo nuevas
// instalaciones). La temporada en web llega por splash + acento + banner.

Future<void> applySeasonalIconImpl(String? variant) async {
  // Intencionalmente vacío.
}
