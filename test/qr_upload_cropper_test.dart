import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/dashboard/payment_methods_screen.dart';

void main() {
  group('QR upload decision — picker + cropper composition', () {
    test('user cancelled picker → abort', () {
      expect(
        decideQrUploadStep(pickedPath: null, croppedPath: null),
        QrUploadStep.abort,
      );
    });
    test('user picked but cancelled cropper → abort (do NOT upload uncropped)', () {
      expect(
        decideQrUploadStep(
            pickedPath: '/tmp/picked.jpg', croppedPath: null),
        QrUploadStep.abort,
      );
    });
    test('cropper returned empty path → abort defensively', () {
      expect(
        decideQrUploadStep(
            pickedPath: '/tmp/picked.jpg', croppedPath: '   '),
        QrUploadStep.abort,
      );
    });
    test('both paths valid → upload the cropped file', () {
      expect(
        decideQrUploadStep(
            pickedPath: '/tmp/picked.jpg',
            croppedPath: '/tmp/cropped.png'),
        QrUploadStep.uploadCropped,
      );
    });
  });
}
