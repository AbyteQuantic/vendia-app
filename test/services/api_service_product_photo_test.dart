// Spec: specs/013-foto-producto-web-ios/spec.md
//
// Regression guard for the product-photo upload path.
//
// Root cause (Spec 013): `ApiService.uploadProductPhoto` took a
// `dart:io File` and built the part with `MultipartFile.fromFile`. On
// Flutter web there is no filesystem and `XFile.path` is a blob URL, so
// that path threw — the product photo never uploaded on the web build.
//
// The fix (D2 / D3): `uploadProductPhoto` now takes an `XFile`, reads its
// BYTES, and normalizes the image to a downsized **PNG** before building
// the multipart part — exactly the `logoMultipart` (F010) pattern. PNG so
// an iPhone HEIC photo also renders on Android (AC-03). The shared
// `ApiService.imageMultipart` helper builds that part and is exercised
// here with the in-memory XFile shape the web image_picker returns
// (`XFile.fromData`) — no filesystem, no network.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:vendia_pos/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds an in-memory XFile backed by a real, decodable image so
  /// `normalizeImageForUpload` (which `imageMultipart` calls) can
  /// process it.
  XFile imageFile({
    int width = 800,
    int height = 600,
    String name = 'foto-producto.png',
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

  group('ApiService.imageMultipart — product-photo upload (Spec 013)', () {
    test(
        'builds a MultipartFile from an in-memory XFile '
        '(the bytes shape the web image_picker returns) — no filesystem path',
        () async {
      final part = await ApiService.imageMultipart(
        imageFile(name: 'foto-producto.png', mimeType: 'image/png'),
        prefix: 'foto',
      );

      expect(part, isA<MultipartFile>());
      expect(part.length, greaterThan(0));
    });

    test(
        'always sends Content-Type image/png so an iPhone HEIC photo '
        'renders on Android too (AC-03)', () async {
      // A PNG source leaves as PNG.
      final fromPng = await ApiService.imageMultipart(
        imageFile(name: 'foto.png', mimeType: 'image/png'),
        prefix: 'foto',
      );
      expect(fromPng.contentType?.mimeType, 'image/png');

      // A JPEG source: still normalized and re-encoded as PNG.
      final fromJpeg = await ApiService.imageMultipart(
        imageFile(name: 'foto.jpg', mimeType: 'image/jpeg', png: false),
        prefix: 'foto',
      );
      expect(fromJpeg.contentType?.mimeType, 'image/png');
    });

    test('uses the given prefix and a .png filename', () async {
      final part = await ApiService.imageMultipart(
        imageFile(name: 'lo-que-el-usuario-eligio.heic'),
        prefix: 'foto',
      );
      expect(part.filename, isNotNull);
      expect(part.filename, startsWith('foto-'));
      expect(part.filename, endsWith('.png'));
    });

    test('downsizes a large image before upload (no 2MB backend error)',
        () async {
      final hugePng = await ApiService.imageMultipart(
        imageFile(width: 3000, height: 3000, name: 'enorme.png'),
        prefix: 'foto',
      );
      final tinyPng = await ApiService.imageMultipart(
        imageFile(width: 200, height: 200, name: 'chica.png'),
        prefix: 'foto',
      );
      expect(hugePng.length, greaterThan(0));
      expect(hugePng.length, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(tinyPng.length, greaterThan(0));
    });

    test(
        'the logo path and the product-photo path share the same '
        'normalize-to-PNG pipeline (only the filename prefix differs)',
        () async {
      final logoPart = await ApiService.logoMultipart(
        imageFile(name: 'mi-logo.png', mimeType: 'image/png'),
      );
      final photoPart = await ApiService.imageMultipart(
        imageFile(name: 'mi-foto.png', mimeType: 'image/png'),
        prefix: 'foto',
      );

      expect(logoPart.contentType?.mimeType, 'image/png');
      expect(photoPart.contentType?.mimeType, 'image/png');
      expect(logoPart.filename, startsWith('logo-'));
      expect(photoPart.filename, startsWith('foto-'));
    });
  });
}
