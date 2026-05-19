// Spec: specs/020-voz-inventario-web/spec.md
//
// Cross-platform voice recording facade — public entry point shared by
// the Voice Inventory screen (F020).
//
// Why this exists: `voice_inventory_screen.dart` used to be mobile-only.
// It imported `dart:io` and called `path_provider`'s
// `getTemporaryDirectory()` to pick a file path before recording.
// `path_provider` has NO web implementation, so that call threw on the
// browser and the mic press did nothing ("ícono no accionable").
//
// `package:record` v6 DOES support web, but with a different contract:
//   - `start(config, path:)` ignores `path` on web.
//   - `stop()` returns a **blob URL** string (not a filesystem path).
//   - the browser's MediaRecorder cannot emit AAC/m4a — it emits
//     WebM/Opus (`AudioEncoder.opus`).
// On mobile the old contract holds: `start` writes to the given path and
// `stop()` returns that path; AAC/m4a works.
//
// This facade hides those differences behind two pieces:
//   1. [recordConfigForPlatform] — the right `RecordConfig` per platform.
//   2. [readRecordedAudio] — turns whatever `stop()` returned (a file
//      path on mobile, a blob URL on web) into upload-ready BYTES plus
//      the real MIME type and a filename.
//
// `dart:io` / `path_provider` live ONLY in `voice_recorder_io.dart`; the
// web build picks `voice_recorder_web.dart` via the conditional import
// below, so the browser never touches them.

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'voice_recorder_io.dart'
    if (dart.library.html) 'voice_recorder_web.dart';

/// An audio clip captured by [AudioRecorder], normalized to bytes so it
/// can be uploaded with `MultipartFile.fromBytes` on every platform.
@immutable
class RecordedAudio {
  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    required this.filename,
  });

  /// Raw audio bytes — m4a on mobile, WebM/Opus on web.
  final Uint8List bytes;

  /// Real MIME type of [bytes], forwarded to the backend so Gemini picks
  /// the right decoder. `audio/m4a` on mobile, `audio/webm` on web.
  final String mimeType;

  /// Filename used for the multipart part. Carries the right extension
  /// so the backend's content sniffing has a hint.
  final String filename;
}

/// Builds the [RecordConfig] that works on the current platform.
///
/// - Web: `AudioEncoder.opus` — the only encoder the browser's
///   MediaRecorder reliably supports (emits WebM/Opus). Forcing
///   `aacLc` would make `record_web` throw "encoder not supported".
/// - Mobile: `AudioEncoder.aacLc` — m4a, the original behavior.
RecordConfig recordConfigForPlatform() {
  if (kIsWeb) {
    return const RecordConfig(
      encoder: AudioEncoder.opus,
      bitRate: 128000,
      sampleRate: 44100,
    );
  }
  return const RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 128000,
    sampleRate: 44100,
  );
}

/// On web `start()` ignores the `path` argument, but `AudioRecorder.start`
/// still requires the named parameter. This builds a path the recorder
/// will use on mobile (temp dir) and ignore on web (a stable placeholder
/// so we never hit `path_provider` in the browser).
Future<String> recordingPath() => resolveRecordingPath();

/// Turns the value returned by [AudioRecorder.stop] into upload-ready
/// [RecordedAudio].
///
/// On mobile [stopResult] is a filesystem path; the bytes are read with
/// `dart:io`. On web it is a blob URL; the bytes are fetched from that
/// URL without ever touching a filesystem.
Future<RecordedAudio> readRecordedAudio(String stopResult) =>
    readRecordedAudioImpl(stopResult);

/// Releases any platform resource tied to [stopResult] after the upload
/// finished — the temp file on mobile, the blob URL on web. Best-effort:
/// failures are swallowed so cleanup never masks a real error.
Future<void> disposeRecordedAudio(String stopResult) =>
    disposeRecordedAudioImpl(stopResult);
