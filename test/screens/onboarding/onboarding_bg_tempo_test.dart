// Spec: specs/048-onboarding-video-bg/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/onboarding/agentic/onboarding_bg_tempo.dart';

void main() {
  group('resolveBgTempo — prioridad de señales', () {
    test('IA/persistencia (busy) manda aunque esté digitando', () {
      expect(resolveBgTempo(busy: true, typing: true), OnboardingBgTempo.busy);
      expect(resolveBgTempo(busy: true, typing: false), OnboardingBgTempo.busy);
    });
    test('digitando sin busy → typing', () {
      expect(resolveBgTempo(busy: false, typing: true), OnboardingBgTempo.typing);
    });
    test('ni busy ni typing → idle (esperando input)', () {
      expect(resolveBgTempo(busy: false, typing: false), OnboardingBgTempo.idle);
    });
  });

  group('bgFpsForTempo — busy acelera, typing es el más lento', () {
    test('orden de velocidades: typing < idle < busy', () {
      final typing = bgFpsForTempo(OnboardingBgTempo.typing);
      final idle = bgFpsForTempo(OnboardingBgTempo.idle);
      final busy = bgFpsForTempo(OnboardingBgTempo.busy);
      expect(typing, lessThan(idle));
      expect(idle, lessThan(busy));
      // busy debe ser claramente más rápido (al menos 2x el idle).
      expect(busy, greaterThanOrEqualTo(idle * 2));
    });
    test('todas las velocidades son positivas', () {
      for (final t in OnboardingBgTempo.values) {
        expect(bgFpsForTempo(t), greaterThan(0));
      }
    });
  });
}
