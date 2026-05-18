// Spec: specs/013-foto-producto-web-ios/spec.md
//
// Web backend for `PickedImagePreview`.
//
// On Flutter web there is no filesystem and `dart:io` cannot be imported,
// so this file (selected by the conditional import when
// `dart.library.html` is available) keeps the web build free of any
// `dart:io` reference.
//
// `PickedImagePreview.build` already handles the web case with
// `Image.network` over the blob URL, so this fallback is only reached if
// the branch logic ever changes. It still renders the blob URL via the
// browser so it never produces a black box.

import 'package:flutter/material.dart';

/// Renders the image at blob-URL [path] with `Image.network` — the
/// browser fetches and decodes the blob itself.
Widget imageFromXFilePath(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.network(
    path,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}
