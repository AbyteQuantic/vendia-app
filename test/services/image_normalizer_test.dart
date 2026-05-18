// Spec: specs/010-logo-heic-iphone/spec.md
//
// Tests for the `normalizeLogoImage` IO path (mobile / non-web), which
// re-encodes a picked logo image to a downsized JPEG with `package:image`.
//
// Why this matters: iPhone photos are HEIC. On Flutter web `image_picker`
// ignores `maxWidth` / `imageQuality`, so the raw image reached the backend
// untouched and Supabase rejected `image/heic`. The fix normalizes every
// logo to JPEG (max side ~1024px, quality ~85) BEFORE upload. These tests
// exercise the IO decoder/resizer; the web path decodes via the browser
// (`<canvas>`), which cannot be unit-tested in the Dart VM.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:vendia_pos/services/image_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds a synthetic [XFile] backed by an encoded image of the given
  /// size, so the test runs entirely in memory (no filesystem, no network).
  XFile syntheticImage({
    required int width,
    required int height,
    required String name,
    required String mimeType,
    bool png = false,
  }) {
    final image = img.Image(width: width, height: height);
    // Fill with a non-uniform gradient so resizing produces real output.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final bytes =
        png ? img.encodePng(image) : img.encodeJpg(image, quality: 95);
    return XFile.fromData(bytes, name: name, mimeType: mimeType);
  }

  group('normalizeLogoImage — IO path (mobile re-encode)', () {
    test('a large JPEG is downsized so the longest side is <= 1024px',
        () async {
      final source = syntheticImage(
        width: 3000,
        height: 2000,
        name: 'foto.jpg',
        mimeType: 'image/jpeg',
      );

      final result = await normalizeLogoImage(source);

      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull,
          reason: 'output must be a valid, decodable image');
      expect(decoded!.width, lessThanOrEqualTo(1024));
      expect(decoded.height, lessThanOrEqualTo(1024));
      // The longest side should be exactly the 1024 cap (aspect kept).
      expect(decoded.width, 1024);
    });

    test('a large PNG is re-encoded as JPEG and downsized', () async {
      final source = syntheticImage(
        width: 2400,
        height: 2400,
        name: 'logo.png',
        mimeType: 'image/png',
        png: true,
      );

      final result = await normalizeLogoImage(source);

      // `findFormatForData` reports the encoded format of the bytes.
      expect(img.findFormatForData(result), img.ImageFormat.jpg,
          reason: 'output must be JPEG regardless of the input format');
      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1024);
      expect(decoded.height, 1024);
    });

    test('a small image keeps its size (no upscaling)', () async {
      final source = syntheticImage(
        width: 300,
        height: 200,
        name: 'pequeno.jpg',
        mimeType: 'image/jpeg',
      );

      final result = await normalizeLogoImage(source);

      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 300);
      expect(decoded.height, 200);
    });

    test('output is always JPEG and decodable', () async {
      final source = syntheticImage(
        width: 1500,
        height: 900,
        name: 'banner.png',
        mimeType: 'image/png',
        png: true,
      );

      final result = await normalizeLogoImage(source);

      expect(result, isNotEmpty);
      expect(img.findFormatForData(result), img.ImageFormat.jpg);
    });

    test('throws a clear exception when the bytes are not a valid image',
        () async {
      final garbage = XFile.fromData(
        // Random bytes that are not any known image format.
        Uint8List.fromList(List<int>.generate(128, (i) => (i * 7) % 256)),
        name: 'roto.bin',
        mimeType: 'application/octet-stream',
      );

      expect(
        () => normalizeLogoImage(garbage),
        throwsA(isA<ImageNormalizationException>()),
      );
    });
  });
}
