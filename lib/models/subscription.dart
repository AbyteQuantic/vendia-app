// Spec: specs/008-planes-suscripcion-epayco/spec.md
//
// Modelos de suscripción para la app Flutter. El backend (Feature 008)
// expone el catálogo de planes y el estado de suscripción del tenant;
// estos modelos los deserializan contra el contrato de `plan.md §4`.
//
// Lección de F1: SIEMPRE leer el `id` que envía el backend — nunca
// generarlo en el cliente para entidades que el servidor posee.

/// Estados del ciclo de vida de la suscripción de un tenant.
/// Reflejan el enum del backend (migración 022).
class SubscriptionStatusValue {
  static const String trial = 'TRIAL';
  static const String free = 'FREE';
  static const String proActive = 'PRO_ACTIVE';
  static const String proPastDue = 'PRO_PAST_DUE';
}

/// Identificadores de plan del catálogo del backend.
class PlanId {
  static const String gratis = 'gratis';
  static const String pro = 'pro';
}

/// Intervalos de facturación soportados por el plan Pro.
class BillingInterval {
  static const String mensual = 'mensual';
  static const String anual = 'anual';
}

/// Un precio de un plan para un intervalo de facturación.
/// Montos en pesos colombianos enteros (Art. VII — dinero exacto).
class PlanPrice {
  /// `mensual` | `anual`.
  final String interval;

  /// Monto en COP enteros (29900, 299000, 0 para el plan gratis).
  final int amount;

  /// Código de moneda ISO. El backend siempre envía `COP`.
  final String currency;

  const PlanPrice({
    required this.interval,
    required this.amount,
    this.currency = 'COP',
  });

  factory PlanPrice.fromJson(Map<String, dynamic> json) {
    return PlanPrice(
      interval: json['interval'] as String? ?? BillingInterval.mensual,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'COP',
    );
  }
}

/// Un plan del catálogo de suscripción (Gratis o Pro).
class SubscriptionPlan {
  /// Identificador del plan tal como lo envía el backend (`gratis`,
  /// `pro`). Lección de F1: se lee, no se inventa.
  final String id;

  /// Nombre legible en español ("Gratis", "Pro").
  final String name;

  /// Descripción corta para mostrar bajo el nombre.
  final String description;

  /// Precios por intervalo. El plan Gratis trae un solo precio en 0;
  /// el plan Pro trae mensual y anual.
  final List<PlanPrice> prices;

  /// Beneficios listados del plan, en español.
  final List<String> features;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.prices,
    required this.features,
  });

  /// `true` cuando el plan no tiene costo (catálogo "Gratis").
  bool get isFree =>
      id == PlanId.gratis || prices.every((p) => p.amount == 0);

  /// Precio para un intervalo dado; `null` si el plan no lo ofrece.
  PlanPrice? priceFor(String interval) {
    for (final price in prices) {
      if (price.interval == interval) return price;
    }
    return null;
  }

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final rawPrices = (json['prices'] as List?) ?? const [];
    final prices = rawPrices
        .cast<Map<String, dynamic>>()
        .map(PlanPrice.fromJson)
        .toList(growable: false);

    // Tolerar la forma plana `monthly_amount` / `yearly_amount` por si
    // el backend la envía sin el arreglo `prices` (retrocompatible).
    if (prices.isEmpty) {
      final monthly = (json['monthly_amount'] as num?)?.toInt();
      final yearly = (json['yearly_amount'] as num?)?.toInt();
      final fallback = <PlanPrice>[];
      if (monthly != null) {
        fallback.add(PlanPrice(
            interval: BillingInterval.mensual, amount: monthly));
      }
      if (yearly != null) {
        fallback.add(PlanPrice(
            interval: BillingInterval.anual, amount: yearly));
      }
      return SubscriptionPlan(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        prices: fallback,
        features: _readFeatures(json),
      );
    }

    return SubscriptionPlan(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      prices: prices,
      features: _readFeatures(json),
    );
  }

  static List<String> _readFeatures(Map<String, dynamic> json) {
    final raw = (json['features'] as List?) ?? const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }
}

/// Estado actual de la suscripción del tenant autenticado.
class SubscriptionStatus {
  /// `TRIAL` | `FREE` | `PRO_ACTIVE` | `PRO_PAST_DUE`. El backend ya
  /// degrada los estados vencidos antes de responder (AC-08).
  final String status;

  /// Plan vigente (`gratis` | `pro`). Puede venir vacío en estados
  /// previos a cualquier elección.
  final String plan;

  /// Intervalo de facturación cuando el plan es Pro.
  final String? interval;

  /// Fecha de vencimiento del período actual (trial o Pro pagado).
  final DateTime? expiresAt;

  /// Días restantes del trial; 0 fuera de trial.
  final int trialDaysRemaining;

  const SubscriptionStatus({
    required this.status,
    required this.plan,
    this.interval,
    this.expiresAt,
    this.trialDaysRemaining = 0,
  });

  /// `true` cuando el tenant tiene acceso a las funciones PRO.
  bool get isPremium =>
      status == SubscriptionStatusValue.proActive ||
      status == SubscriptionStatusValue.trial;

  /// `true` cuando el tenant está en período de prueba.
  bool get isTrial => status == SubscriptionStatusValue.trial;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value);
    }

    return SubscriptionStatus(
      status: json['status'] as String? ?? SubscriptionStatusValue.free,
      plan: json['plan'] as String? ?? '',
      interval: json['interval'] as String?,
      // El backend puede nombrar el campo `expires_at` o
      // `current_period_end` (ver spec §8) — se aceptan ambos.
      expiresAt: parseDate(json['expires_at']) ??
          parseDate(json['current_period_end']) ??
          parseDate(json['trial_ends_at']),
      trialDaysRemaining:
          (json['trial_days_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Datos que devuelve `POST /subscription/checkout` para abrir la
/// pasarela de ePayco. El webhook es la fuente de verdad de la
/// promoción a Pro (D2); estos datos solo abren el checkout.
class CheckoutSession {
  /// Referencia única generada por el backend para esta transacción.
  final String reference;

  /// URL del checkout de ePayco a la que se debe enviar al usuario.
  /// Cuando el backend entrega los parámetros sueltos en vez de una
  /// URL ya armada, este campo puede venir vacío y la UI usa
  /// [checkoutData] / [publicKey].
  final String checkoutUrl;

  /// Monto del cobro en COP enteros.
  final int amount;

  /// Descripción del cobro que se muestra en el checkout.
  final String description;

  /// Plan e intervalo cobrados, devueltos para refrescar la UI.
  final String plan;
  final String? interval;

  /// Parámetros crudos del checkout de ePayco (`public_key`, `name`,
  /// `currency`, `response`, `confirmation`, etc.) por si la UI debe
  /// armar el formulario en vez de redirigir a una URL.
  final Map<String, dynamic> checkoutData;

  const CheckoutSession({
    required this.reference,
    required this.checkoutUrl,
    required this.amount,
    required this.description,
    required this.plan,
    this.interval,
    this.checkoutData = const {},
  });

  /// `true` cuando el backend entregó una URL directa para redirigir.
  bool get hasUrl => checkoutUrl.isNotEmpty;

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    final rawData = json['checkout_data'];
    return CheckoutSession(
      reference: json['reference'] as String? ??
          json['ref'] as String? ??
          json['ref_payco'] as String? ??
          '',
      checkoutUrl: json['checkout_url'] as String? ??
          json['url'] as String? ??
          '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      description: json['description'] as String? ?? '',
      plan: json['plan'] as String? ?? '',
      interval: json['interval'] as String?,
      checkoutData: rawData is Map
          ? rawData.cast<String, dynamic>()
          : const {},
    );
  }
}
