import 'package:flutter/material.dart';

/// Growth Radar — surfaces the merchant's progress toward the
/// configurable annual revenue threshold. It is intentionally
/// celebratory, never punitive: the palette stays in green/blue,
/// the copy avoids regulatory or threatening language, and the
/// card adapts to five bands of progress (`RadarBand`).
///
/// Usage:
///   GrowthRadarCard(
///     revenue: 80_000_000,
///     threshold: 160_000_000,
///     taxAlreadyActive: TaxSettingsService.instance.enabled,
///     onActivateTaxTap: () => Navigator.push(...),
///   );
enum RadarBand { sustained, onTrack, prepare, celebrating, urgent }

/// Pure mapping from progress percentage to a band. Kept top-level
/// so it can be unit-tested without spinning up widgets.
RadarBand bandFor(double pct) {
  if (pct < 0.5) return RadarBand.sustained;
  if (pct < 0.7) return RadarBand.onTrack;
  if (pct < 0.85) return RadarBand.prepare;
  if (pct < 0.95) return RadarBand.celebrating;
  return RadarBand.urgent;
}

/// Visual style for each band. Colors stay in the green/blue family
/// — never red, never amber-warning. Only the celebrating + urgent
/// bands surface a CTA.
class RadarBandStyle {
  const RadarBandStyle({
    required this.emoji,
    required this.headline,
    required this.start,
    required this.end,
    required this.showCta,
  });

  final String emoji;
  final String headline;
  final Color start;
  final Color end;
  final bool showCta;

  static RadarBandStyle forBand(RadarBand band) {
    switch (band) {
      case RadarBand.sustained:
        return const RadarBandStyle(
          emoji: '🌱',
          headline: 'Crecimiento sostenido',
          start: Color(0xFFDCFCE7),
          end: Color(0xFFBBF7D0),
          showCta: false,
        );
      case RadarBand.onTrack:
        return const RadarBandStyle(
          emoji: '📈',
          headline: 'Va por buen camino',
          start: Color(0xFFDBEAFE),
          end: Color(0xFFBFDBFE),
          showCta: false,
        );
      case RadarBand.prepare:
        return const RadarBandStyle(
          emoji: '🛡️',
          headline: 'Considere prepararse',
          start: Color(0xFFBFDBFE),
          end: Color(0xFF93C5FD),
          showCta: false,
        );
      case RadarBand.celebrating:
        return const RadarBandStyle(
          emoji: '🎉',
          headline: '¡Felicitaciones — está cerca!',
          start: Color(0xFF6EE7B7),
          end: Color(0xFF3B82F6),
          showCta: true,
        );
      case RadarBand.urgent:
        return const RadarBandStyle(
          emoji: '🛡️',
          headline: 'Es momento de formalizar',
          start: Color(0xFF2563EB),
          end: Color(0xFF0EA5E9),
          showCta: true,
        );
    }
  }
}

/// Reusable card. Caller passes raw revenue / threshold (in COP);
/// the card derives the band and renders accordingly. The widget
/// is pure presentation — fetching the live revenue, threshold,
/// and tax-active state is the screen's responsibility.
class GrowthRadarCard extends StatelessWidget {
  const GrowthRadarCard({
    super.key,
    required this.revenue,
    required this.threshold,
    this.compact = false,
    this.onActivateTaxTap,
    this.taxAlreadyActive = false,
  });

  final double revenue;
  final int threshold;
  final bool compact;
  final VoidCallback? onActivateTaxTap;
  final bool taxAlreadyActive;

  /// Visual progress, capped at 1.5 so the card never renders an
  /// outlandish ratio if revenue runs far past the threshold.
  double get pct {
    if (threshold <= 0) return 0;
    final raw = revenue / threshold;
    if (raw < 0) return 0;
    if (raw > 1.5) return 1.5;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final band = bandFor(pct);
    final style = RadarBandStyle.forBand(band);
    final progressValue = pct.clamp(0.0, 1.0).toDouble();
    final pctText = '${(pct * 100).round()}%';
    final subtitle =
        'Ha vendido ${_formatMoney(revenue)} de ${_formatMoney(threshold.toDouble())} este año';

    final pad = compact ? 12.0 : 18.0;
    final headlineSize = compact ? 14.0 : 16.0;
    final emojiSize = compact ? 24.0 : 28.0;

    // Whites and translucent whites anchor text + progress against
    // the green/blue gradient. Picking a darker text color for the
    // pale "sustained" / "onTrack" bands keeps contrast accessible.
    final isPaleBand =
        band == RadarBand.sustained || band == RadarBand.onTrack;
    final textColor =
        isPaleBand ? const Color(0xFF0F172A) : Colors.white;
    final subtitleColor = isPaleBand
        ? const Color(0xFF0F172A).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.92);
    final progressBg = isPaleBand
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.35);
    final progressFg = isPaleBand
        ? const Color(0xFF2563EB)
        : Colors.white;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [style.start, style.end],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(style.emoji, style: TextStyle(fontSize: emojiSize)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            style.headline,
                            style: TextStyle(
                              fontSize: headlineSize,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          pctText,
                          style: TextStyle(
                            fontSize: headlineSize,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: subtitleColor,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: compact ? 5 : 7,
                        backgroundColor: progressBg,
                        valueColor: AlwaysStoppedAnimation<Color>(progressFg),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (style.showCta) ...[
            SizedBox(height: compact ? 8 : 12),
            _buildCtaRow(textColor),
          ],
        ],
      ),
    );
  }

  Widget _buildCtaRow(Color textColor) {
    if (taxAlreadyActive) {
      // Active state — celebrate completion instead of nagging.
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '✅ IVA Configurado',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      );
    }
    if (onActivateTaxTap == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: onActivateTaxTap,
        style: TextButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.95),
          foregroundColor: const Color(0xFF1E40AF),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: const Text(
          'Activar IVA',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Colombian peso formatter mirroring the dashboard's existing style
/// ("$1.234.567"). Kept private because it is incidental to the
/// widget and not meant to be reused elsewhere.
String _formatMoney(double amount) {
  final cents = amount.round();
  if (cents == 0) return r'$0';
  final s = cents.abs().toString();
  final buf = StringBuffer(cents < 0 ? r'-$' : r'$');
  final start = s.length % 3;
  if (start > 0) buf.write(s.substring(0, start));
  for (int i = start; i < s.length; i += 3) {
    if (i > 0) buf.write('.');
    buf.write(s.substring(i, i + 3));
  }
  return buf.toString();
}
