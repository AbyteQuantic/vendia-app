// Spec: specs/013-foto-producto-web-ios/spec.md
//
// Tests for `PickedImagePreview`, the cross-platform preview of an image
// the merchant just picked.
//
// Root cause (Spec 013): the product-photo screens previewed the picked
// image with `Image.file(File(xfile.path))`. On Flutter web there is no
// filesystem and `XFile.path` is a blob URL, so the preview rendered as a
// black box. `PickedImagePreview` branches on `kIsWeb`: `Image.network`
// over the blob URL on web, `Image.file` on mobile.
//
// These tests run in the Dart VM, i.e. the NON-web (`kIsWeb == false`)
// branch, so they pin the mobile `Image.file` path — proving F013 did not
// regress the native apps (AC-04). The web `Image.network` branch is
// covered by the `kIsWeb` switch in `build` and verified in the deployed
// `vendia.store` build (Constitution Art. XII).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:vendia_pos/widgets/picked_image_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Writes a real, decodable 4x4 PNG to a temp file and returns an XFile
  /// pointing at it — the shape native `image_picker` returns.
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('picked_image_preview_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  XFile pngOnDisk(String name) {
    final image = img.Image(width: 4, height: 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        image.setPixelRgb(x, y, 10 * x, 10 * y, 30);
      }
    }
    final file = File('${tempDir.path}/$name')
      ..writeAsBytesSync(img.encodePng(image));
    return XFile(file.path);
  }

  testWidgets('renders an Image widget for a picked file (mobile branch)',
      (tester) async {
    final xfile = pngOnDisk('foto.png');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickedImagePreview(file: xfile, width: 80, height: 80),
        ),
      ),
    );

    // The mobile branch must build an `Image` — never a bare black
    // container, the Spec 013 bug symptom.
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('forwards width, height, fit and errorBuilder to the Image',
      (tester) async {
    final xfile = pngOnDisk('foto.png');
    ImageErrorWidgetBuilder errorBuilder(_, __, ___) =>
        (a, b, c) => const SizedBox.shrink();
    final builder = errorBuilder(null, null, null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickedImagePreview(
            file: xfile,
            width: 120,
            height: 64,
            fit: BoxFit.contain,
            errorBuilder: builder,
          ),
        ),
      ),
    );

    // The mobile branch must hand the dimensions, fit and the caller's
    // errorBuilder (the placeholder that replaces the Spec 013 black box)
    // straight to the underlying `Image`.
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 120);
    expect(image.height, 64);
    expect(image.fit, BoxFit.contain);
    expect(image.errorBuilder, same(builder));
  });
}
