// Spec: specs/007-web-logo-upload/spec.md
//
// Regression guard for the web logo-upload bug: the onboarding logo
// step used to wrap the picked image in a `dart:io File(xfile.path)`
// and send it via `MultipartFile.fromFile`. On Flutter web there is no
// filesystem and `XFile.path` is only a blob URL, so that path threw
// and the merchant saw a generic "intente más tarde" error (FR-01).
//
// The fix routes every platform through `ApiService.logoMultipart`,
// which reads the picked image as BYTES (`XFile.readAsBytes`) and
// builds a `MultipartFile.fromBytes`. These tests exercise that helper
// with the in-memory XFile shape the web image_picker returns
// (`XFile.fromData`) — no filesystem, no network.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vendia_pos/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1x1 PNG-ish payload — content is irrelevant, only the bytes path.
  final sampleBytes = Uint8List.fromList(
    List<int>.generate(64, (i) => i % 256),
  );

  // The test VM runs the dart:io XFile implementation, where the
  // filename comes from `path` (the web build instead honours `name`).
  // We pass `path` so XFile.name resolves on both — `logoMultipart`
  // only ever reads `XFile.name`, so the behaviour is identical.
  XFile bytesFile({String? path, String? mimeType}) => XFile.fromData(
        sampleBytes,
        path: path,
        mimeType: mimeType,
      );

  group('ApiService.logoMultipart (cross-platform bytes upload)', () {
    test(
        'builds a MultipartFile from an in-memory XFile '
        '(the bytes shape image_picker returns) without a filesystem path',
        () async {
      final picked = bytesFile(path: 'mi-logo.png', mimeType: 'image/png');

      final part = await ApiService.logoMultipart(picked);

      expect(part, isA<MultipartFile>());
      expect(part.length, sampleBytes.length);
      expect(part.filename, 'mi-logo.png');
      expect(part.contentType?.mimeType, 'image/png');
    });

    test('preserves the byte length so the server receives the full image',
        () async {
      final part =
          await ApiService.logoMultipart(bytesFile(path: 'logo.jpg'));
      expect(part.length, 64);
    });

    test('falls back to a synthesized filename when XFile.name is empty',
        () async {
      // No path → XFile.name is empty → helper synthesizes one.
      final part = await ApiService.logoMultipart(bytesFile());
      expect(part.filename, isNotNull);
      expect(part.filename, isNotEmpty);
      expect(part.filename, endsWith('.jpg'));
    });

    test('derives MIME from the extension when XFile.mimeType is null',
        () async {
      // Mobile pickers frequently leave mimeType null.
      final part =
          await ApiService.logoMultipart(bytesFile(path: 'brand.webp'));
      expect(part.contentType?.mimeType, 'image/webp');
    });

    test('honours an explicit XFile.mimeType over the extension', () async {
      final part = await ApiService.logoMultipart(
        bytesFile(path: 'brand.bin', mimeType: 'image/png'),
      );
      expect(part.contentType?.mimeType, 'image/png');
    });
  });

  group('ApiService.mimeFromName', () {
    test('maps known image extensions case-insensitively', () {
      expect(ApiService.mimeFromName('logo.PNG'), 'image/png');
      expect(ApiService.mimeFromName('logo.webp'), 'image/webp');
      expect(ApiService.mimeFromName('logo.GIF'), 'image/gif');
      expect(ApiService.mimeFromName('photo.heic'), 'image/heic');
      expect(ApiService.mimeFromName('photo.HEIF'), 'image/heic');
    });

    test('defaults to image/jpeg for unknown or missing extensions', () {
      expect(ApiService.mimeFromName('logo.jpg'), 'image/jpeg');
      expect(ApiService.mimeFromName('logo'), 'image/jpeg');
      expect(ApiService.mimeFromName('logo.bmp'), 'image/jpeg');
    });
  });
}
