// Spec: specs/019-foto-perfil-tendero-empleado/spec.md
//
// Guard for the profile-photo upload path (owner / employee).
//
// Spec 019 / FR-04, AC-04: `ApiService.uploadEmployeePhoto` must take an
// `XFile` — never a `dart:io File` — read its BYTES and normalize the
// image to a downsized PNG before building the multipart part, exactly
// like `uploadProductPhoto` (F013) and `logoMultipart` (F010). Reading
// bytes is what makes the upload work on Flutter web (no filesystem,
// `XFile.path` is only a blob URL) and on iOS Safari (HEIC -> PNG).
//
// The multipart part is built by the shared `ApiService.imageMultipart`
// helper with the `perfil` prefix. These tests exercise that helper with
// the in-memory XFile shape the web image_picker returns
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
  /// process it — the bytes shape the web image_picker returns.
  XFile imageFile({
    int width = 800,
    int height = 600,
    String name = 'foto-perfil.png',
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

  group('ApiService.imageMultipart — profile photo (Spec 019)', () {
    test(
        'builds a MultipartFile from an in-memory XFile '
        '(the bytes shape the web image_picker returns) — no filesystem path',
        () async {
      final part = await ApiService.imageMultipart(
        imageFile(name: 'foto-perfil.png', mimeType: 'image/png'),
        prefix: 'perfil',
      );

      expect(part, isA<MultipartFile>());
      expect(part.length, greaterThan(0));
    });

    test(
        'always sends Content-Type image/png so an iPhone HEIC photo '
        'renders on Android too (AC-03, AC-04)', () async {
      final fromPng = await ApiService.imageMultipart(
        imageFile(name: 'perfil.png', mimeType: 'image/png'),
        prefix: 'perfil',
      );
      expect(fromPng.contentType?.mimeType, 'image/png');

      // A JPEG source is still normalized and re-encoded as PNG.
      final fromJpeg = await ApiService.imageMultipart(
        imageFile(name: 'perfil.jpg', mimeType: 'image/jpeg', png: false),
        prefix: 'perfil',
      );
      expect(fromJpeg.contentType?.mimeType, 'image/png');
    });

    test('uses the "perfil" prefix and a .png filename', () async {
      final part = await ApiService.imageMultipart(
        imageFile(name: 'lo-que-el-usuario-eligio.heic'),
        prefix: 'perfil',
      );
      expect(part.filename, isNotNull);
      expect(part.filename, startsWith('perfil-'));
      expect(part.filename, endsWith('.png'));
    });

    test('downsizes a large photo before upload (no 2MB backend error)',
        () async {
      final hugePng = await ApiService.imageMultipart(
        imageFile(width: 3000, height: 3000, name: 'enorme.png'),
        prefix: 'perfil',
      );
      expect(hugePng.length, greaterThan(0));
      expect(hugePng.length, lessThanOrEqualTo(2 * 1024 * 1024));
    });
  });
}
