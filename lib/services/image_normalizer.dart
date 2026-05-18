// Spec: specs/010-logo-heic-iphone/spec.md
//
// Logo image normalization — public, cross-platform facade.
//
// Why this exists: iPhone photos are HEIC. On Flutter web `image_picker`
// ignores `maxWidth` / `imageQuality`, so a raw HEIC reached the backend
// untouched; the Supabase `store-logos` bucket only accepts
// jpeg/png/webp/gif and rejected `image/heic` -> 500 "error al subir logo".
//
// The fix: re-encode every logo to a downsized JPEG BEFORE upload.
//   - Web   -> decode with the BROWSER (a `<canvas>`), which on Safari can
//              decode HEIC, then export `image/jpeg`. See
//              `image_normalizer_web.dart`.
//   - Mobile / other -> decode with `package:image`. See
//              `image_normalizer_io.dart`.
//
// The conditional import picks the right implementation at compile time.
// Shared types (`ImageNormalizationException`, the size/quality constants)
// live in `image_normalizer_types.dart` so both implementations and this
// facade can reference them without an import cycle.

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'image_normalizer_io.dart'
    if (dart.library.html) 'image_normalizer_web.dart';
import 'image_normalizer_types.dart';

export 'image_normalizer_types.dart'
    show ImageNormalizationException, kLogoMaxSide, kLogoJpegQuality;

/// Re-encodes [source] into a downsized **JPEG** suitable for upload to the
/// `store-logos` bucket.
///
/// - The longest side is capped at [kLogoMaxSide]; smaller images are not
///   upscaled.
/// - Output is always JPEG at [kLogoJpegQuality] quality.
///
/// Throws [ImageNormalizationException] (with a Spanish message) when the
/// image cannot be decoded.
Future<Uint8List> normalizeLogoImage(XFile source) =>
    normalizeLogoImageImpl(source);
