// Spec: specs/013-foto-producto-web-ios/spec.md
//
// IO (mobile / desktop) backend for `PickedImagePreview`.
//
// On a native platform `XFile.path` is a real filesystem path, so the
// picked image is rendered with `Image.file(File(path))`. `dart:io` is
// imported here — never in the web build — because this file is only
// selected by the conditional import on non-web platforms.

import 'dart:io';

import 'package:flutter/material.dart';

/// Renders the image at filesystem [path] with `Image.file`.
Widget imageFromXFilePath(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}
