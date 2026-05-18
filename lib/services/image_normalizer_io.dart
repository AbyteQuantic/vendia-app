// Spec: specs/010-logo-heic-iphone/spec.md
//
// Logo image normalization — IO (mobile / non-web) implementation.
//
// On mobile the image_picker already honours `maxWidth` / `imageQuality`,
// but routing every platform through the same normalizer guarantees a
// JPEG output and a downsized image regardless of what the picker returns
// (some Android galleries hand back the original file untouched).
//
// Decoding here uses `package:image` (pure Dart). The web path instead
// decodes with the browser — see `image_normalizer_web.dart`.

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'image_normalizer_types.dart';

/// IO implementation of `normalizeLogoImage`. Selected by the conditional
/// import in `image_normalizer.dart` on every non-web platform.
Future<Uint8List> normalizeLogoImageImpl(XFile source) async {
  final bytes = await source.readAsBytes();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    // `package:image` could not recognize the bytes as any image format.
    throw const ImageNormalizationException(
      'No pudimos procesar esa foto. Intente con otra, o tome una captura '
      'de pantalla de la foto y súbala.',
    );
  }

  final resized = _resizeToFit(decoded);
  return img.encodeJpg(resized, quality: kLogoJpegQuality);
}

/// Returns [image] resized so its longest side is at most [kLogoMaxSide].
/// Smaller images are returned unchanged — never upscaled.
img.Image _resizeToFit(img.Image image) {
  final longestSide =
      image.width >= image.height ? image.width : image.height;
  if (longestSide <= kLogoMaxSide) {
    return image;
  }
  // Constrain the longest side and let `package:image` keep the aspect
  // ratio for the other dimension.
  if (image.width >= image.height) {
    return img.copyResize(image, width: kLogoMaxSide);
  }
  return img.copyResize(image, height: kLogoMaxSide);
}
