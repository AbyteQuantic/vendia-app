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

/// Web: [stopResult] is a blob URL — fetch the blob and read its bytes +
/// its REAL MIME type. The type is no longer hardcoded to webm: it can be
/// `audio/mp4` (Safari/iOS), `audio/webm` (Chrome) or `audio/wav` (the
/// universal fallback), and Gemini needs the right one to pick a decoder.
Future<RecordedAudio> readRecordedAudioImpl(String stopResult) async {
  final blob = await _fetchBlob(stopResult);
  final bytes = await _blobToBytes(blob);
  // El MIME debe coincidir con los BYTES reales o Gemini no decodifica y el
  // backend responde `degraded` (el "no hay señal" en iPhone). Por eso el
  // contenido manda: 1) magic bytes del contenedor, 2) blob.type si es claro,
  // 3) WAV como último recurso (Web Audio funciona en todos y Gemini lo lee).
  final sniffed = _sniffMime(bytes);
  final rawType = (blob.type).toLowerCase().split(';').first.trim();
  final mime = sniffed ?? (rawType.isNotEmpty ? rawType : 'audio/wav');
  return RecordedAudio(
    bytes: bytes,
    mimeType: mime,
    filename: 'vendia_voice.${_extForMime(mime)}',
  );
}

/// Detecta el contenedor de audio por su firma (magic bytes). Devuelve el MIME
/// real o null si no reconoce la firma. Robusto en iOS Safari, donde `blob.type`
/// suele venir vacío y delataba el formato como webm por error.
String? _sniffMime(Uint8List b) {
  if (b.length < 12) return null;
  bool eq(int off, List<int> sig) {
    for (var i = 0; i < sig.length; i++) {
      if (b[off + i] != sig[i]) return false;
    }
    return true;
  }

  // RIFF....WAVE → WAV
  if (eq(0, [0x52, 0x49, 0x46, 0x46]) && eq(8, [0x57, 0x41, 0x56, 0x45])) {
    return 'audio/wav';
  }
  // 0x1A45DFA3 → Matroska/WebM
  if (eq(0, [0x1A, 0x45, 0xDF, 0xA3])) return 'audio/webm';
  // 'OggS' → Ogg
  if (eq(0, [0x4F, 0x67, 0x67, 0x53])) return 'audio/ogg';
  // ....'ftyp' → contenedor ISO-BMFF (mp4/m4a, lo que graba iOS con aacLc)
  if (eq(4, [0x66, 0x74, 0x79, 0x70])) return 'audio/mp4';
  // 'ID3' o frame sync 0xFFEx/0xFFFx → MP3
  if (eq(0, [0x49, 0x44, 0x33]) || (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0)) {
    return 'audio/mpeg';
  }
  return null;
}

/// Maps an audio MIME type to a sensible file extension (a hint for the
/// backend's content sniffing).
String _extForMime(String mime) {
  if (mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
    return 'mp4';
  }
  if (mime.contains('wav')) return 'wav';
  if (mime.contains('ogg')) return 'ogg';
  if (mime.contains('mpeg') || mime.contains('mp3')) return 'mp3';
  return 'webm';
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

/// Fetches the [html.Blob] behind a `blob:` URL (so we can read its real
/// `.type`). Local read of an in-memory blob — never hits the network.
Future<html.Blob> _fetchBlob(String blobUrl) async {
  final request = await html.HttpRequest.request(
    blobUrl,
    responseType: 'blob',
  );
  final resp = request.response;
  if (resp is html.Blob) return resp;
  throw StateError('No se pudo leer el audio grabado en el navegador.');
}

/// Reads a [html.Blob] into bytes via FileReader (arraybuffer).
Future<Uint8List> _blobToBytes(html.Blob blob) async {
  final reader = html.FileReader();
  reader.readAsArrayBuffer(blob);
  await reader.onLoadEnd.first;
  final result = reader.result;
  if (result is ByteBuffer) return result.asUint8List();
  if (result is Uint8List) return result;
  throw StateError('No se pudo leer el audio grabado en el navegador.');
}
