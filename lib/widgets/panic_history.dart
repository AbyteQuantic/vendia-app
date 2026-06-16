// Spec: specs/057-panic-button-delivery/spec.md
//
// Lista del histórico de alertas de pánico para la pantalla de
// Seguridad: por cada alerta, fecha + a quién se avisó y con qué estado.

import 'package:flutter/material.dart';

import '../models/panic_alert.dart';

class PanicHistory extends StatelessWidget {
  final List<PanicAlert> alerts;

  const PanicHistory({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Aún no ha activado el botón de pánico. Cuando lo haga, aquí verá '
          'a quién se le avisó y si el mensaje llegó.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280), height: 1.35),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in alerts)
          Padding(
            key: Key('panic_alert_${a.id}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: _AlertCard(alert: a),
          ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final PanicAlert alert;
  const _AlertCard({required this.alert});

  String _date(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626), size: 18),
              const SizedBox(width: 6),
              Text(
                _date(alert.triggeredAt),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                'Se avisó a ${alert.contactCount}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final d in alert.deliveries)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    d.method == 'sms'
                        ? Icons.sms_rounded
                        : Icons.chat_rounded,
                    size: 14,
                    color: const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d.contactName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: d.statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      d.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: d.statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
