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

/// Builds the [RecordConfig] for the current platform (sync, mobile-only
/// default). Kept for back-compat; the screen uses [resolveRecordConfig]
/// so the web path can negotiate the encoder at runtime.
RecordConfig recordConfigForPlatform() {
  return const RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 128000,
    sampleRate: 44100,
  );
}

/// Web-only ordered list of encoders to try, best-compatible first:
///   1. opus  → WebM/Opus (Chrome, Firefox, Android web).
///   2. aacLc → audio/mp4  (Safari/iOS — the ONLY MediaRecorder codec it
///      supports; Opus made `start()` throw "encoder not supported",
///      which is exactly why the mic "did nothing" on iPhone).
///   3. wav   → record_web records WAV via the Web Audio API (NOT
///      MediaRecorder), so it works on every browser as a last resort.
const List<AudioEncoder> _webEncoderPreference = [
  AudioEncoder.opus,
  AudioEncoder.aacLc,
  AudioEncoder.wav,
];

/// Picks the [RecordConfig] that actually works in THIS browser.
///
/// The same web bundle runs on Chrome (Opus) and Safari/iOS (mp4 only),
/// so the choice must be made at runtime by asking the recorder which
/// encoders it supports — a compile-time default can't be right for both.
/// On mobile (and the test VM) `kIsWeb` is false → returns the AAC config
/// unchanged, preserving the original behavior and not touching the
/// injected recorder in widget tests.
///
/// Voice is speech: mono @ 16 kHz keeps uploads small (a 90 s WAV stays
/// well under the backend's 10 MB cap) without hurting Gemini's accuracy.
Future<RecordConfig> resolveRecordConfig(AudioRecorder recorder) async {
  if (!kIsWeb) return recordConfigForPlatform();

  for (final enc in _webEncoderPreference) {
    try {
      if (await recorder.isEncoderSupported(enc)) {
        return RecordConfig(
          encoder: enc,
          bitRate: 128000,
          sampleRate: 16000,
          numChannels: 1,
        );
      }
    } catch (_) {
      // isEncoderSupported can throw on exotic browsers — try the next.
    }
  }
  // Universal fallback: WAV via Web Audio works even if every
  // MediaRecorder codec probe failed.
  return const RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
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
