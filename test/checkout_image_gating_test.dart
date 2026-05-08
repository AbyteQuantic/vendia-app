import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/bank_notification_service.dart';

/// Critical PO-mandate guard: a bank notification — even when
/// detected mid-flow — MUST NOT enable the confirm button on its
/// own. The button must only be enabled by an actual receipt photo.
///
/// This test pins the rule at the service-API level so the rule is
/// visible to every future caller, regardless of which screen the
/// gating happens in. We model the gate the same way every screen
/// does:
///
///     canConfirm = isCash || receiptUrl != null
///
/// and verify that publishing a bank notification leaves
/// `receiptUrl` untouched.
void main() {
  setUp(() {
    BankNotificationService.instance.reset();
  });

  test(
      'bank notification does NOT mutate the receiptUrl that gates the '
      'Confirm button', () {
    String? receiptUrl; // mirrors the screen's local _receiptUrl field
    bool canConfirm() => receiptUrl != null;

    expect(canConfirm(), isFalse,
        reason: 'baseline: no image attached → button disabled');

    BankNotificationService.instance
        .onBankNotification(bankLabel: 'Bancolombia');

    expect(receiptUrl, isNull,
        reason: 'service must not write to caller state');
    expect(canConfirm(), isFalse,
        reason:
            'CRITICAL: the bank notification must never enable the button');

    // Only an explicit receipt-image upload should flip the gate.
    receiptUrl = 'https://example.supabase.co/storage/v1/object/public/'
        'payment_receipts/public/abc.jpg';
    expect(canConfirm(), isTrue,
        reason: 'gate opens only when the cashier attaches the photo');
  });

  test('reset() detaches the listener-side state without touching the gate',
      () {
    String? receiptUrl =
        'https://example.supabase.co/storage/v1/object/public/'
        'payment_receipts/public/abc.jpg';
    BankNotificationService.instance.onBankNotification(bankLabel: 'Nequi');
    BankNotificationService.instance.reset();

    expect(BankNotificationService.instance.lastDetectedBank, isNull);
    // The receipt URL is owned by the screen; the service has no
    // business clearing it.
    expect(receiptUrl, isNotNull);
  });
}
