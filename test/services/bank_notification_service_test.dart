import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/bank_notification_service.dart';

/// Mandatory Image Receipts epic — the bank notification listener is
/// strictly informative. Tests pin that contract: the service may
/// publish a label, but it never carries decision rights for any
/// payment confirmation.
void main() {
  setUp(() {
    BankNotificationService.instance.reset();
  });

  test('onBankNotification updates last fields and notifies listeners', () {
    final svc = BankNotificationService.instance;
    var notifyCount = 0;
    svc.addListener(() => notifyCount++);

    svc.onBankNotification(bankLabel: 'Bancolombia');

    expect(svc.lastDetectedBank, 'Bancolombia');
    expect(svc.lastDetectedAt, isNotNull);
    expect(notifyCount, 1);
  });

  test('reset clears the cached bank label and timestamp', () {
    final svc = BankNotificationService.instance;
    svc.onBankNotification(bankLabel: 'Nequi');
    svc.reset();

    expect(svc.lastDetectedBank, isNull);
    expect(svc.lastDetectedAt, isNull);
  });
}
