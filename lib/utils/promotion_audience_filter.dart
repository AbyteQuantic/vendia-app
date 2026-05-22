// Spec: specs/033-difusion-promociones/spec.md
//
// Filtros RFM pre-armados del selector de audiencia (F033 — spec §4).
//
// Cada filtro es una segmentación basada en los agregados del modelo
// Customer de F030 (`total_spent`, `purchase_count`, `last_purchase_at`).
// El cálculo real lo hace el backend (plan §5 — queries con índice); el
// frontend solo manda el `wire` del filtro elegido.

/// Segmentos pre-armados de clientes para la difusión de una promoción.
enum PromotionAudienceFilter {
  /// Todos los clientes con teléfono registrado.
  all,

  /// ≥3 compras en los últimos 30 días.
  frequent,

  /// Top 20% por gasto histórico.
  vip,

  /// Sin compras en los últimos 30 días.
  dormant,

  /// Compraron en los últimos 7 días.
  recent,

  /// Selección manual por checkbox — no es un segmento, lo arma el dueño.
  manual;

  /// Valor que viaja al backend (`POST /promotions/:id/audience`).
  String get wire => name;

  /// Etiqueta corta para los FilterChips.
  String get label {
    switch (this) {
      case PromotionAudienceFilter.all:
        return 'Todos';
      case PromotionAudienceFilter.frequent:
        return 'Frecuentes';
      case PromotionAudienceFilter.vip:
        return 'VIP';
      case PromotionAudienceFilter.dormant:
        return 'Dormidos';
      case PromotionAudienceFilter.recent:
        return 'Recientes';
      case PromotionAudienceFilter.manual:
        return 'A mano';
    }
  }

  /// Descripción del criterio para que el dueño entienda el segmento.
  String get description {
    switch (this) {
      case PromotionAudienceFilter.all:
        return 'Todos sus clientes con teléfono';
      case PromotionAudienceFilter.frequent:
        return '3 o más compras en los últimos 30 días';
      case PromotionAudienceFilter.vip:
        return 'Los que más le han comprado';
      case PromotionAudienceFilter.dormant:
        return 'Sin comprarle hace más de un mes';
      case PromotionAudienceFilter.recent:
        return 'Compraron en los últimos 7 días';
      case PromotionAudienceFilter.manual:
        return 'Elija usted mismo a quién avisarle';
    }
  }
}
