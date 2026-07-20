// Spec: specs/106-onboarding-conversacional-agente/spec.md (Adenda A)
// Guardián de calidad de forma: la silueta de usuario debe ser simétrica y
// con cabeza redonda — evita regresiones "deformes" (feedback fundador).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/onboarding/vendi/vendi_orb.dart';

void main() {
  test('silueta user: simétrica en x y cabeza redonda', () {
    final pts = debugVendiShapePoints(VendiOrbShape.user);
    expect(pts.length, 160);

    // Simetría: para cada punto debe existir su espejo (-x, y) cercano.
    var worst = 0.0;
    for (final p in pts) {
      var best = double.infinity;
      for (final q in pts) {
        final d = math.sqrt(math.pow(q.dx + p.dx, 2) + math.pow(q.dy - p.dy, 2));
        if (d < best) best = d;
      }
      if (best > worst) worst = best;
    }
    expect(worst, lessThan(0.05), reason: 'asimetría máxima $worst');

    // Cabeza: los puntos sobre y>0.3 deben quedar a distancia ~constante del
    // centro de la cabeza (círculo, no bulto).
    final head = pts.where((p) => p.dy > .30).toList();
    final rs = head
        .map((p) => math.sqrt(math.pow(p.dx, 2) + math.pow(p.dy - .40, 2)))
        .toList();
    final avg = rs.reduce((a, b) => a + b) / rs.length;
    for (final r in rs) {
      expect((r - avg).abs() / avg, lessThan(0.08),
          reason: 'cabeza no circular');
    }
  });
}
