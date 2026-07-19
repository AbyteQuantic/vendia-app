// Hotfix bucle "sesión expiró" (2026-07-19) — dedup del aviso.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';

void main() {
  setUp(() => ApiService.lastSessionExpiredNoticeAt = null);

  test('una ráfaga de 401s produce UN solo aviso', () {
    final t0 = DateTime(2026, 7, 19, 14, 52);
    expect(ApiService.shouldNotifySessionExpired(t0), isTrue);
    // 401s concurrentes milisegundos después → suprimidos.
    expect(
        ApiService.shouldNotifySessionExpired(
            t0.add(const Duration(milliseconds: 50))),
        isFalse);
    expect(
        ApiService.shouldNotifySessionExpired(t0.add(const Duration(seconds: 15))),
        isFalse);
  });

  test('pasada la ventana de 30s puede volver a avisar', () {
    final t0 = DateTime(2026, 7, 19, 14, 52);
    expect(ApiService.shouldNotifySessionExpired(t0), isTrue);
    expect(
        ApiService.shouldNotifySessionExpired(t0.add(const Duration(seconds: 31))),
        isTrue);
  });
}
