// Spec: specs/020-voz-inventario-web/spec.md
//
// Voice recording — web implementation. Selected by the conditional
// import in `voice_recorder.dart` when `dart.library.html` is available.
//
// On the browser `package:record` records through the MediaRecorder API.
// `start(config, path:)` IGNORES the `path` argument and `stop()` returns
// a **blob URL** (`blob:https://...`) pointing at the recorded clip held
// in browser memory. There is no filesystem and no `path_provider`.
//
// To upload the clip we fetch its bytes straight from the blob URL with
// `HttpRequest` (a same-origin fetch of an in-memory blob — no network).
// The clip is WebM/Opus because that is what the browser's MediaRecorder
// produces for `AudioEncoder.opus`.
//
// `dart:html` is web-only and deprecated but still the supported path on
// the current Flutter web SDK — `image_normalizer_web.dart` uses it the
// same way. A future migration to `package:web` would touch only this
// file.
//
// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'voice_recorder.dart';

/// Web: the `record` API ignores `path` on the browser, but
/// `AudioRecorder.start` still requires the named argument. Return a
/// stable placeholder so the call site never has to branch and the
/// browser never reaches `path_provider`.
Future<String> resolveRecordingPath() async =>
    'vendia_voice_web.webm';

/// Web: [stopResult] is a blob URL — fetch its bytes from browser memory.
Future<RecordedAudio> readRecordedAudioImpl(String stopResult) async {
  final bytes = await _fetchBlobBytes(stopResult);
  return RecordedAudio(
    bytes: bytes,
    // The browser's MediaRecorder emits WebM/Opus for AudioEncoder.opus.
    mimeType: 'audio/webm',
    filename: 'vendia_voice.webm',
  );
}

/// Web: revoke the blob URL so the browser frees the in-memory clip.
/// Best-effort — a stale or already-revoked URL is harmless.
Future<void> disposeRecordedAudioImpl(String stopResult) async {
  try {
    html.Url.revokeObjectUrl(stopResult);
  } catch (_) {
    // Revoking an unknown URL is a no-op in practice; never surface it.
  }
}

/// Reads the bytes behind a `blob:` URL via an arraybuffer XHR. This is a
/// local read of an in-memory blob — it never hits the network.
Future<Uint8List> _fetchBlobBytes(String blobUrl) async {
  final request = await html.HttpRequest.request(
    blobUrl,
    responseType: 'arraybuffer',
  );
  final buffer = request.response;
  if (buffer is ByteBuffer) {
    return buffer.asUint8List();
  }
  // Defensive: an unexpected response shape means the clip is unusable.
  throw StateError('No se pudo leer el audio grabado en el navegador.');
}
