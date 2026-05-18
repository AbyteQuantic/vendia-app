// Spec: specs/010-logo-heic-iphone/spec.md
//
// Logo image normalization — WEB implementation.
//
// Why decode with the BROWSER instead of `package:image`: iPhone photos
// are HEIC and `package:image` cannot decode HEIC. Safari (the browser an
// iPhone user runs) CAN decode HEIC natively. So on web we hand the raw
// bytes to the browser via an `<img>` element, draw it onto a `<canvas>`
// resized to the cap, and export `image/jpeg` from the canvas. The
// merchant's own browser does the HEIC -> JPEG conversion for us.
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

/// Web implementation of `normalizeLogoImage`. Selected by the conditional
/// import in `image_normalizer.dart` when `dart.library.html` is available.
Future<Uint8List> normalizeLogoImageImpl(XFile source) async {
  final bytes = await source.readAsBytes();

  // Wrap the raw bytes in a Blob and hand it to the browser as an <img>.
  // The browser decoder runs here — this is what makes HEIC work on Safari.
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

/// Draws [image] onto a downsized `<canvas>` and exports it as JPEG bytes.
Uint8List _drawAndExport(html.ImageElement image) {
  final srcWidth = image.naturalWidth;
  final srcHeight = image.naturalHeight;
  if (srcWidth == 0 || srcHeight == 0) {
    throw const ImageNormalizationException(_cannotProcessMessage);
  }

  final scaled = _scaledSize(srcWidth, srcHeight);

  final canvas = html.CanvasElement(
    width: scaled.width,
    height: scaled.height,
  );
  final ctx = canvas.context2D;
  ctx.drawImageScaled(image, 0, 0, scaled.width, scaled.height);

  // `toDataUrl` returns "data:image/jpeg;base64,<payload>"; decode the
  // base64 payload to the JPEG bytes the upload expects.
  final dataUrl = canvas.toDataUrl('image/jpeg', kLogoJpegQuality / 100);
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0) {
    throw const ImageNormalizationException(_cannotProcessMessage);
  }
  return base64Decode(dataUrl.substring(commaIndex + 1));
}

/// Target canvas size: the longest side capped at [kLogoMaxSide], aspect
/// ratio preserved. Smaller images are kept at their original size.
({int width, int height}) _scaledSize(int srcWidth, int srcHeight) {
  final longestSide = srcWidth >= srcHeight ? srcWidth : srcHeight;
  if (longestSide <= kLogoMaxSide) {
    return (width: srcWidth, height: srcHeight);
  }
  final scale = kLogoMaxSide / longestSide;
  final width = (srcWidth * scale).round().clamp(1, kLogoMaxSide);
  final height = (srcHeight * scale).round().clamp(1, kLogoMaxSide);
  return (width: width, height: height);
}
