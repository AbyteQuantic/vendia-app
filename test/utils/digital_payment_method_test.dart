import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/digital_payment_method.dart';

void main() {
  group('isDigitalPaymentMethod — excluded cash', () {
    test('cash → false', () {
      expect(isDigitalPaymentMethod('cash'), isFalse);
    });
    test('efectivo (Spanish synonym) → false', () {
      expect(isDigitalPaymentMethod('efectivo'), isFalse);
    });
    test('CASH (uppercase) → false (lowercased internally)', () {
      expect(isDigitalPaymentMethod('CASH'), isFalse);
    });
  });

  group('isDigitalPaymentMethod — excluded credit / fiado', () {
    test('credit → false (unpaid debt)', () {
      expect(isDigitalPaymentMethod('credit'), isFalse);
    });
    test('fiado (Spanish synonym) → false', () {
      expect(isDigitalPaymentMethod('fiado'), isFalse);
    });
  });

  group('isDigitalPaymentMethod — excluded multi (conservative)', () {
    test('multi → false (no breakdown stored, conservative call)', () {
      expect(isDigitalPaymentMethod('multi'), isFalse);
    });
  });

  group('isDigitalPaymentMethod — digital methods', () {
    test('transfer → true', () {
      expect(isDigitalPaymentMethod('transfer'), isTrue);
    });
    test('card → true', () {
      expect(isDigitalPaymentMethod('card'), isTrue);
    });
    test('nequi → true', () {
      expect(isDigitalPaymentMethod('nequi'), isTrue);
    });
    test('daviplata → true', () {
      expect(isDigitalPaymentMethod('daviplata'), isTrue);
    });
    test('NEQUI (uppercase) → true', () {
      expect(isDigitalPaymentMethod('NEQUI'), isTrue);
    });
    test('"  Nequi  " (padded) → true (trim normalizes)', () {
      expect(isDigitalPaymentMethod('  Nequi  '), isTrue);
    });
    test('tenant custom name "Bancolombia QR" → true', () {
      expect(isDigitalPaymentMethod('Bancolombia QR'), isTrue);
    });
  });

  group('isDigitalPaymentMethod — null / blank input', () {
    test('null → false', () {
      expect(isDigitalPaymentMethod(null), isFalse);
    });
    test('empty string → false', () {
      expect(isDigitalPaymentMethod(''), isFalse);
    });
    test('whitespace only → false (trim collapses to empty)', () {
      expect(isDigitalPaymentMethod('   '), isFalse);
    });
  });
}
