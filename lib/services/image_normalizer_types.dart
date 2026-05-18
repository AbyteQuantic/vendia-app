// Spec: specs/010-logo-heic-iphone/spec.md
//
// Shared types & constants for logo image normalization. Kept in a
// dependency-free file so both the IO and web implementations and the
// public facade can import it without forming an import cycle.

/// Maximum length (in pixels) of the longest side of a normalized logo.
/// JPEG quality ~85 at this size keeps the file well under the 2MB cap.
const int kLogoMaxSide = 1024;

/// JPEG encoding quality used for normalized logos (0-100).
const int kLogoJpegQuality = 85;

/// Thrown when a picked image cannot be decoded / re-encoded — e.g. the
/// bytes are corrupt, or the browser cannot decode the source format
/// (a non-Safari browser handed a HEIC file).
///
/// The [message] is in Spanish so callers can surface it directly to the
/// merchant (Constitution Art. V). Never swallow this exception silently.
class ImageNormalizationException implements Exception {
  const ImageNormalizationException(this.message);

  /// User-facing Spanish message describing what happened and what to do.
  final String message;

  @override
  String toString() => 'ImageNormalizationException: $message';
}
