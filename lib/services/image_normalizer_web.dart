// Spec: specs/010-logo-heic-iphone/spec.md
//
// Logo image normalization — WEB implementation.
//
// Why decode with the BROWSER instead of `package:image`: iPhone photos
// are HEIC and `package:image` cannot decode HEIC. Safari (the browser an
// iPhone user runs) CAN decode HEIC natively. So on web we hand the raw
// bytes to the browser via an `<img>` element, draw it onto a `<canvas>`
// resized to the cap, and export the canvas. The merchant's own browser
// does the HEIC -> raster conversion for us.
//
// Spec 010 §9 / D1: the canvas is exported as **PNG** (`image/png`), not
// JPEG. A `<canvas>` is RGBA, so a logo with a transparent background
// (the usual ChatGPT / Nano Banana / Gemini output) keeps its alpha when
// exported to PNG. Exporting `image/jpeg` would composite that alpha onto
// the canvas's opaque black backing -> a black box. We also never paint a
// background fill before `drawImage`, so the transparent pixels stay
// transparent.
//
// If the browser cannot decode the source (a non-Safari browser handed a
// HEIC file), the `<img>` fires `onError` and we throw a clear Spanish
// `ImageNormalizationException` — never a silent failure.
//
// `dart:html` is deprecated but still works on the current Flutter web
// engine; it is isolated behind this conditional-import file so a future
// migration to `package:web` only touches this one file.

import 'dart:async';
import 'dart:convert';
// `dart:html` is deprecated and web-only. Both are deliberate here: this
// file is only ever compiled into the web build (via the conditional
// import in `image_normalizer.dart`), and it needs the browser's native
// image decoder — the one thing that can decode iPhone HEIC (Spec 010,
// plan §6). It is isolated to this single file for an easy future
// migration to `package:web`.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'image_normalizer_types.dart';

const _cannotProcessMessage = 'No pudimos procesar esa foto. Intente con '
    'otra, o tome una captura de pantalla de la foto y súbala.';

const _tooHeavyMessage = 'Esa imagen es demasiado pesada. Intente con una '
    'foto más sencilla o con menos detalle.';

/// Web implementation of `normalizeLogoImage`. Selected by the conditional
/// import in `image_normalizer.dart` when `dart.library.html` is available.
Future<Uint8List> normalizeLogoImageImpl(XFile source) async {
  final bytes = await source.readAsBytes();

  // Wrap the raw bytes in a Blob and hand it to the browser as an <img>.
  // The browser decoder runs here — this is what makes HEIC work on
  // Safari, and PNG/WebP (with alpha) on every browser.
  final blob = html.Blob(<dynamic>[bytes]);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);

  try {
    final image = await _loadImage(objectUrl);
    return _drawAndExport(image);
  } finally {
    // Always release the blob URL, success or failure.
    html.Url.revokeObjectUrl(objectUrl);
  }
}

/// Loads [objectUrl] into an [html.ImageElement], completing when the
/// browser has decoded it. Throws [ImageNormalizationException] if the
/// browser cannot decode the source format.
Future<html.ImageElement> _loadImage(String objectUrl) {
  final completer = Completer<html.ImageElement>();
  final image = html.ImageElement();

  // `onLoad` / `onError` fire exactly once each; capture subscriptions so
  // we can cancel the other after the first event.
  late final StreamSubscription<html.Event> loadSub;
  late final StreamSubscription<html.Event> errorSub;

  loadSub = image.onLoad.listen((_) {
    errorSub.cancel();
    loadSub.cancel();
    if (!completer.isCompleted) {
      completer.complete(image);
    }
  });

  errorSub = image.onError.listen((_) {
    loadSub.cancel();
    errorSub.cancel();
    if (!completer.isCompleted) {
      // The browser could not decode the bytes — typically a non-Safari
      // browser handed a HEIC file. Surface a clear, actionable message.
      completer.completeError(
        const ImageNormalizationException(_cannotProcessMessage),
      );
    }
  });

  image.src = objectUrl;
  return completer.future;
}

/// Draws [image] onto a downsized `<canvas>` and exports it as PNG bytes.
///
/// PNG keeps the canvas's alpha channel, so a transparent logo stays
/// transparent. If a pathological input produces a PNG over
/// [kLogoMaxBytes], the canvas is redrawn at progressively smaller sizes
/// until it fits, mirroring the IO path's fallback.
Uint8List _drawAndExport(html.ImageElement image) {
  final srcWidth = image.naturalWidth;
  final srcHeight = image.naturalHeight;
  if (srcWidth == 0 || srcHeight == 0) {
    throw const ImageNormalizationException(_cannotProcessMessage);
  }

  var maxSide = kLogoMaxSide;
  while (true) {
    final png = _exportPngAt(image, srcWidth, srcHeight, maxSide);
    if (png.length <= kLogoMaxBytes || maxSide <= kLogoMinSide) {
      if (png.length > kLogoMaxBytes) {
        // Even at the minimum side the PNG is too heavy — refuse rather
        // than upload an image the backend would reject with a 2MB error.
        throw const ImageNormalizationException(_tooHeavyMessage);
      }
      return png;
    }
    maxSide = (maxSide ~/ 2).clamp(kLogoMinSide, kLogoMaxSide);
  }
}

/// Renders [image] onto a canvas whose longest side is capped at [maxSide]
/// and exports it as PNG bytes.
Uint8List _exportPngAt(
  html.ImageElement image,
  int srcWidth,
  int srcHeight,
  int maxSide,
) {
  final scaled = _scaledSize(srcWidth, srcHeight, maxSide);

  final canvas = html.CanvasElement(
    width: scaled.width,
    height: scaled.height,
  );
  // A fresh <canvas> starts fully transparent. We deliberately do NOT
  // paint a background fill, so a transparent source logo keeps its
  // transparency once exported as PNG.
  final ctx = canvas.context2D;
  ctx.drawImageScaled(image, 0, 0, scaled.width, scaled.height);

  // `toDataUrl('image/png')` keeps the alpha channel; `image/jpeg` would
  // not. It returns "data:image/png;base64,<payload>"; decode the base64
  // payload to the PNG bytes the upload expects.
  final dataUrl = canvas.toDataUrl('image/png');
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0) {
    throw const ImageNormalizationException(_cannotProcessMessage);
  }
  return base64Decode(dataUrl.substring(commaIndex + 1));
}

/// Target canvas size: the longest side capped at [maxSide], aspect ratio
/// preserved. Smaller images are kept at their original size.
({int width, int height}) _scaledSize(
  int srcWidth,
  int srcHeight,
  int maxSide,
) {
  final longestSide = srcWidth >= srcHeight ? srcWidth : srcHeight;
  if (longestSide <= maxSide) {
    return (width: srcWidth, height: srcHeight);
  }
  final scale = maxSide / longestSide;
  final width = (srcWidth * scale).round().clamp(1, maxSide);
  final height = (srcHeight * scale).round().clamp(1, maxSide);
  return (width: width, height: height);
}
