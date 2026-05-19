// Spec: specs/020-voz-inventario-web/spec.md
//
// Voice recording — IO (mobile / non-web) implementation. Selected by the
// conditional import in `voice_recorder.dart` when `dart.library.html` is
// NOT available.
//
// On mobile `package:record` writes the clip to a real file path and
// `stop()` returns that path. The clip is m4a (AAC). This file is the
// ONLY place `dart:io` and `path_provider` are referenced, so the web
// build never sees them.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'voice_recorder.dart';

/// Mobile: a real temp-dir path the recorder writes the m4a clip to.
Future<String> resolveRecordingPath() async {
  final tempDir = await getTemporaryDirectory();
  return '${tempDir.path}/vendia_voice_'
      '${DateTime.now().millisecondsSinceEpoch}.m4a';
}

/// Mobile: [stopResult] is a filesystem path — read the file as bytes.
Future<RecordedAudio> readRecordedAudioImpl(String stopResult) async {
  final bytes = await File(stopResult).readAsBytes();
  return RecordedAudio(
    bytes: Uint8List.fromList(bytes),
    mimeType: 'audio/m4a',
    filename: 'vendia_voice.m4a',
  );
}

/// Mobile: delete the temp file. Best-effort — a missing file is fine.
Future<void> disposeRecordedAudioImpl(String stopResult) async {
  try {
    await File(stopResult).delete();
  } on FileSystemException {
    // The file may already be gone, or never existed (e.g. a test path).
    // Cleanup failure must not surface to the user.
  }
}
