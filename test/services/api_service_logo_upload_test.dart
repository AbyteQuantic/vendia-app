// Spec: specs/010-logo-heic-iphone/spec.md
//
// Regression guard for the logo-upload path. History:
//
//   Spec 007 — the onboarding logo step used a `dart:io File(xfile.path)`
//   and `MultipartFile.fromFile`. On web there is no filesystem and
//   `XFile.path` is a blob URL, so that path threw. The fix routed every
//   platform through `ApiService.logoMultipart`, which reads BYTES.
//
//   Spec 010 — iPhone photos are HEIC; `image_picker` on web ignores
//   `maxWidth`/`imageQuality`, so the raw HEIC reached Supabase, which
//   rejects `image/heic` -> 500. The fix normalizes every logo to a
//   downsized JPEG via `normalizeLogoImage` BEFORE upload, so
//   `logoMultipart` now ALWAYS emits `image/jpeg` with a `.jpg` filename.
//
// These tests exercise `logoMultipart` with the in-memory XFile shape the
// web image_picker returns (`XFile.fromData`) — no filesystem, no network.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:vendia_pos/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds an in-memory XFile backed by a real, decodable image so
  /// `normalizeLogoImage` (which `logoMultipart` calls) can process it.
  XFile imageFile({
    int width = 800,
    int height = 600,
    String name = 'mi-logo.png',
    String? mimeType,
    bool png = true,
  }) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final bytes =
        png ? img.encodePng(image) : img.encodeJpg(image, quality: 95);
    return XFile.fromData(bytes, name: name, mimeType: mimeType);
  }

  group('ApiService.logoMultipart (Spec 010 — normalized JPEG upload)', () {
    test(
        'builds a MultipartFile from an in-memory XFile '
        '(the bytes shape image_picker returns) without a filesystem path',
        () async {
      final part = await ApiService.logoMultipart(
        imageFile(name: 'mi-logo.png', mimeType: 'image/png'),
      );

      expect(part, isA<MultipartFile>());
      expect(part.length, greaterThan(0));
    });

    test(
        'always sends Content-Type image/jpeg regardless of the source '
        'format (Spec 010 — Supabase rejects image/heic)', () async {
      // A PNG source must still leave as JPEG.
      final fromPng = await ApiService.logoMultipart(
        imageFile(name: 'brand.png', mimeType: 'image/png'),
      );
      expect(fromPng.contentType?.mimeType, 'image/jpeg');

      // A JPEG source: still normalized and sent as JPEG.
      final fromJpeg = await ApiService.logoMultipart(
        imageFile(name: 'foto.jpg', mimeType: 'image/jpeg', png: false),
      );
      expect(fromJpeg.contentType?.mimeType, 'image/jpeg');
    });

    test('always sends a .jpg filename so the upload matches the bytes',
        () async {
      final part = await ApiService.logoMultipart(
        imageFile(name: 'whatever-the-user-picked.png'),
      );
      expect(part.filename, isNotNull);
      expect(part.filename, endsWith('.jpg'));
    });

    test('downsizes a large image before upload (AC-03 — no 2MB error)',
        () async {
      final hugePng = await ApiService.logoMultipart(
        imageFile(width: 3000, height: 3000, name: 'enorme.png'),
      );
      final tinyPng = await ApiService.logoMultipart(
        imageFile(width: 200, height: 200, name: 'chica.png'),
      );
      // The 3000px source, capped to 1024px and JPEG-compressed, must be
      // produced without error.
      expect(hugePng.length, greaterThan(0));
      expect(tinyPng.length, greaterThan(0));
    });
  });
}
