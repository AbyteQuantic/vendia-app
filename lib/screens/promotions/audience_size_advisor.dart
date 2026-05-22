// Spec: specs/033-difusion-promociones/spec.md
//
// Banner contextual del asistente de tamaño de audiencia (F033 — spec
// §4.5 mejora 3, AC-06c).
//
// Según cuántos clientes seleccionó el dueño, el banner cambia el tono:
//   - ≤20  → verde, "arranca directo".
//   - 21-50 → ámbar, estima el tiempo de la cola asistida.
//   - >50  → azul fuerte, sugiere la Lista de Difusión nativa o la
//            Fase 2 (F034 — WhatsApp Business API) con tiempos y costos
//            honestos sobre la mesa.
//
// El banner es solo informativo: no bloquea. Cuando hay un CTA de Lista
// de Difusión, [onUseBroadcastList] lo cablea.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Tramo de tamaño de audiencia — define el tono del banner.
enum AudienceSizeTier { small, medium, large }

/// Clasifica un [count] de audiencia en su tramo.
AudienceSizeTier audienceSizeTier(int count) {
  if (count <= 20) return AudienceSizeTier.small;
  if (count <= 50) return AudienceSizeTier.medium;
  return AudienceSizeTier.large;
}

/// Estima los minutos de la cola asistida: ~3s de countdown + ~5s de
/// interacción del dueño por cliente ⇒ ~8s/cliente.
int estimatedQueueMinutes(int count) {
  if (count <= 0) return 0;
  final minutes = (count * 8 / 60).ceil();
  return minutes < 1 ? 1 : minutes;
}

/// Banner que aconseja al dueño según el tamaño de la audiencia.
class AudienceSizeAdvisor extends StatelessWidget {
  /// Número de clientes seleccionados.
  final int count;

  /// Callback del CTA "Usar Lista de Difusión". Solo se muestra en el
  /// tramo grande (>50) cuando el padre lo cablea.
  final VoidCallback? onUseBroadcastList;

  const AudienceSizeAdvisor({
    super.key,
    required this.count,
    this.onUseBroadcastList,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final tier = audienceSizeTier(count);
    final minutes = estimatedQueueMinutes(count);

    final (Color color, IconData icon, String message) = switch (tier) {
      AudienceSizeTier.small => (
          AppTheme.success,
          Icons.bolt_rounded,
          'Audiencia pequeña ($count). Puede empezar la cola '
              'directamente — le toma menos de 3 minutos.',
        ),
      AudienceSizeTier.medium => (
          AppTheme.warning,
          Icons.schedule_rounded,
          'Esto le tomará unos ~$minutes minutos en la cola asistida. '
              'Si prefiere, use la Lista de Difusión de WhatsApp.',
        ),
      AudienceSizeTier.large => (
          AppTheme.primary,
          Icons.groups_rounded,
          'Audiencia grande ($count). La cola le tomaría ~$minutes '
              'minutos. Para hacerlo de un solo toque, cree una Lista '
              'de Difusión de WhatsApp Business (gratis) — o active la '
              'Fase 2 (envío automático, próximamente).',
        ),
    };

    return Container(
      key: const Key('audience_size_advisor'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (tier == AudienceSizeTier.large &&
              onUseBroadcastList != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('advisor_use_broadcast_list'),
                onPressed: onUseBroadcastList,
                icon: const Icon(Icons.contacts_rounded, size: 20),
                label: const Text(
                  'Crear Lista de Difusión',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
