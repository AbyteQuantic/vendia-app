import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/growth_radar_card.dart';

/// Pure unit tests for [bandFor]. Boundaries (0.5, 0.7, 0.85, 0.95)
/// must land in the *higher* band so the celebratory + urgent steps
/// trigger exactly when the spec says.
void main() {
  group('bandFor — band boundaries', () {
    test('0.0 → sustained', () {
      expect(bandFor(0.0), RadarBand.sustained);
    });

    test('0.49 → sustained', () {
      expect(bandFor(0.49), RadarBand.sustained);
    });

    test('0.50 → onTrack (boundary)', () {
      expect(bandFor(0.50), RadarBand.onTrack);
    });

    test('0.69 → onTrack', () {
      expect(bandFor(0.69), RadarBand.onTrack);
    });

    test('0.70 → prepare (boundary)', () {
      expect(bandFor(0.70), RadarBand.prepare);
    });

    test('0.84 → prepare', () {
      expect(bandFor(0.84), RadarBand.prepare);
    });

    test('0.85 → celebrating (boundary)', () {
      expect(bandFor(0.85), RadarBand.celebrating);
    });

    test('0.94 → celebrating', () {
      expect(bandFor(0.94), RadarBand.celebrating);
    });

    test('0.95 → urgent (boundary)', () {
      expect(bandFor(0.95), RadarBand.urgent);
    });

    test('1.0 → urgent', () {
      expect(bandFor(1.0), RadarBand.urgent);
    });

    test('1.5 → urgent (over capped)', () {
      expect(bandFor(1.5), RadarBand.urgent);
    });
  });

  group('RadarBandStyle — palette is green/blue, never red', () {
    test('sustained / onTrack / prepare → showCta == false', () {
      expect(RadarBandStyle.forBand(RadarBand.sustained).showCta, isFalse);
      expect(RadarBandStyle.forBand(RadarBand.onTrack).showCta, isFalse);
      expect(RadarBandStyle.forBand(RadarBand.prepare).showCta, isFalse);
    });

    test('celebrating / urgent → showCta == true', () {
      expect(RadarBandStyle.forBand(RadarBand.celebrating).showCta, isTrue);
      expect(RadarBandStyle.forBand(RadarBand.urgent).showCta, isTrue);
    });

    test('headlines stay in non-threatening / non-regulatory tone', () {
      const banned = ['DIAN', 'sanción', 'sancion', 'multa', 'Multa', 'rojo'];
      for (final band in RadarBand.values) {
        final h = RadarBandStyle.forBand(band).headline;
        for (final word in banned) {
          expect(h.contains(word), isFalse,
              reason: 'Band ${band.name} headline contains banned word "$word": $h');
        }
      }
    });
  });
}
