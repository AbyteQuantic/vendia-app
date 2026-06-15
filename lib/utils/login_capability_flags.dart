// Spec: specs/051-login-emite-capacidades/spec.md
//
// Las capacidades opcionales nuevas (F029–F037) viajan como llaves TOP-LEVEL de
// la respuesta de /login, NO dentro del sub-objeto `feature_flags` (que solo
// trae los 7 flags viejos). Si el login solo persiste `data['feature_flags']`,
// el dashboard degrada un módulo ACTIVO (Recetas/menú, Marketing, …) a "Descubre
// más opciones" en cada inicio de sesión. Esta función mergea esas llaves
// top-level dentro del mapa de flags para que `FeatureFlags.fromJson` (que ya
// las entiende) las persista.

/// Llaves de capacidad que el backend emite en la RAÍZ del login (Spec 051).
const kLoginCapabilityKeys = <String>[
  'enable_recipes',
  'enable_marketing_hub',
  'enable_quotes',
  'enable_promotions',
  'enable_customer_management',
  'enable_supplies',
  'enable_furniture_jobs',
  'enable_purchase_orders',
  'enable_price_tiers',
];

/// Devuelve el sub-objeto `feature_flags` (7 flags viejos) mergeado con las
/// capacidades top-level presentes en [data]. Nunca lanza; tolera `data` sin
/// `feature_flags` o sin capacidades.
Map<String, dynamic> foldLoginCapabilityFlags(Map<String, dynamic> data) {
  final merged = <String, dynamic>{
    ...?(data['feature_flags'] as Map<String, dynamic>?),
  };
  for (final k in kLoginCapabilityKeys) {
    if (data.containsKey(k)) merged[k] = data[k];
  }
  return merged;
}
