// Spec: specs/013-foto-producto-web-ios/spec.md
//
// Cross-platform preview for an image the merchant just picked or took
// (an `XFile` from `image_picker`).
//
// Why this widget exists: the product-photo screens previewed the picked
// image with `Image.file(File(xfile.path))`. On Flutter web there is no
// filesystem and `XFile.path` is a blob URL, so `Image.file` failed and
// the preview rendered as the container's background — a black box
// (Spec 013, root cause).
//
// The fix branches on `kIsWeb`:
//   - Web    -> `Image.network(xfile.path)`. `XFile.path` on web is a
//               `blob:` URL the browser can fetch and decode itself. The
//               browser's decoder handles HEIC on Safari, so an iPhone
//               photo previews correctly without any re-encode.
//   - Mobile -> `Image.file(File(xfile.path))`. Native `image_picker`
//               returns a real filesystem path and a JPEG, which
//               `Image.file` renders directly — no regression.
//
// This is preview-only. The actual upload always goes through
// `ApiService.uploadProductPhoto`, which normalizes the image to PNG so
// it also renders on Android.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'picked_image_preview_io.dart'
    if (dart.library.html) 'picked_image_preview_web.dart';

/// Shows the [file] the merchant just picked, cross-platform.
///
/// On web the preview is `Image.network` over the blob URL; on mobile it
/// is `Image.file`. [width], [height] and [fit] mirror the `Image`
/// constructor. [errorBuilder] is invoked when the image fails to load —
/// callers should surface a placeholder, never a black box.
class PickedImagePreview extends StatelessWidget {
  const PickedImagePreview({
    super.key,
    required this.file,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  /// The image the merchant picked or captured.
  final XFile file;

  /// Optional fixed width for the rendered image.
  final double? width;

  /// Optional fixed height for the rendered image.
  final double? height;

  /// How the image is inscribed into its box. Defaults to [BoxFit.cover].
  final BoxFit fit;

  /// Builds the fallback shown when the image cannot be decoded.
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // `XFile.path` is a blob URL on web — let the browser decode it.
      return Image.network(
        file.path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
    // Mobile / desktop: `XFile.path` is a real filesystem path.
    return imageFromXFilePath(
      file.path,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}
