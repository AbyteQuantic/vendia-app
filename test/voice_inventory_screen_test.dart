import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:vendia_pos/screens/inventory/voice_inventory_screen.dart';
import 'package:vendia_pos/services/voice_recorder.dart';

/// Widget tests for the Phase-4 Voice Inventory screen.
///
/// Spec 020 made the screen cross-platform. The recording path no longer
/// depends on `path_provider`/`dart:io File` directly — the screen reads
/// the clip through the `voice_recorder.dart` facade. The screen exposes
/// four injectable seams so a test never touches the microphone,
/// `path_provider`, a filesystem, a browser blob, or the network:
///   1. `recorder`     — a fake AudioRecorder.
///   2. `apiCall`      — the upload lambda (Spec 020: receives `Uint8List`).
///   3. `resolvePath`  — the path passed to `recorder.start` (no
///                       `path_provider` in the test VM).
///   4. `readAudio`    — turns `recorder.stop()`'s result into bytes (no
///                       file read / blob fetch in the test VM).
///
/// The mic orb is activated via a GestureDetector whose onTapDown +
/// onTapUp fire synchronously with `tester.press`/`releasePointer`,
/// letting us exercise the state machine without a long-press
/// simulation library.

class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({this.grantPermission = true});

  final bool grantPermission;
  String stopResult = 'fake-clip';

  bool started = false;
  bool stopped = false;
  bool disposed = false;

  // record 6.x introduced the `request` named param; override the full
  // signature so the analyzer is happy on both current and future
  // releases that keep the same call shape.
  @override
  Future<bool> hasPermission({bool request = true}) async => grantPermission;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    started = true;
  }

  @override
  Future<String?> stop() async {
    stopped = true;
    return stopResult;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  // All other AudioRecorder methods are unused by the widget. Throw
  // explicitly so a future refactor that starts calling one fails
  // loud in tests instead of silently no-opping.
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeRecorder: ${invocation.memberName}');
}

/// A recorder whose `start` throws — stands in for the web failure mode
/// where the recording-start path used to throw an unhandled exception
/// (`path_provider` has no web implementation).
class _ThrowingRecorder implements AudioRecorder {
  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    throw StateError('recorder unavailable');
  }

  @override
  Future<void> dispose() async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ThrowingRecorder: ${invocation.memberName}');
}

/// Test seam: a fixed path, no `path_provider`.
Future<String> _fakePath() async => 'fake-clip';

/// Test seam: fixed bytes, no filesystem / blob fetch.
Future<RecordedAudio> _fakeAudio(String _) async => RecordedAudio(
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
      mimeType: 'audio/webm',
      filename: 'vendia_voice.webm',
    );

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initial state renders mic orb + "mantén presionado" hint',
      (tester) async {
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: _FakeRecorder(),
      apiCall: ({required audioBytes, required mimeType, required filename}) async => [],
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    expect(find.byKey(const Key('voice_mic_button')), findsOneWidget);
    expect(find.byKey(const Key('voice_status_idle')), findsOneWidget);
    expect(find.text('Mantén presionado para grabar'), findsOneWidget);
  });

  testWidgets('tap on mic transitions idle → recording and starts recorder',
      (tester) async {
    final recorder = _FakeRecorder();
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: recorder,
      apiCall: ({required audioBytes, required mimeType, required filename}) async => [],
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final micFinder = find.byKey(const Key('voice_mic_button'));
    final center = tester.getCenter(micFinder);
    final gesture = await tester.startGesture(center);
    await tester.pump(); // allow onTapDown → startRecording to run

    expect(recorder.started, isTrue);
    expect(find.byKey(const Key('voice_status_recording')), findsOneWidget);

    // Hold a beat so the elapsed guard (>=1.2s) passes on release.
    // The recording-duration guard keys on DateTime.now() (real time),
    // so pump()'s virtual clock won't move it. runAsync sleeps the
    // real event loop while still letting the widget tree pump frames.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    await gesture.up();
    await tester.pump(); // onTapUp → stopAndSend (processing)

    expect(recorder.stopped, isTrue);
  });

  testWidgets('release under 1.2s shows "grabación muy corta" hint',
      (tester) async {
    final recorder = _FakeRecorder();
    int apiCalls = 0;
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: recorder,
      apiCall: ({required audioBytes, required mimeType, required filename}) async {
        apiCalls++;
        return [];
      },
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final micFinder = find.byKey(const Key('voice_mic_button'));
    final center = tester.getCenter(micFinder);
    final gesture = await tester.startGesture(center);
    await tester.pump();
    // Release immediately (< 1.2 s)
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    // pumpAndSettle can't be used — the mic orb runs continuous
    // pulse + wave animations that never settle. runAsync flushes
    // the real event loop so async chains (recorder.stop → apiCall
    // → setState → unawaited cleanup) resolve, then a discrete
    // pump rebuilds the tree with the new state.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(apiCalls, 0,
        reason: 'short taps must never burn a Gemini round trip');
    expect(find.byKey(const Key('voice_status_error')), findsOneWidget);
    expect(find.textContaining('muy corta'), findsOneWidget);
  });

  testWidgets('API error surfaces the inline error status', (tester) async {
    final recorder = _FakeRecorder();
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: recorder,
      apiCall: ({required audioBytes, required mimeType, required filename}) async {
        throw Exception('boom');
      },
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final micFinder = find.byKey(const Key('voice_mic_button'));
    final gesture = await tester.startGesture(tester.getCenter(micFinder));
    await tester.pump();
    // The recording-duration guard keys on DateTime.now() (real time),
    // so pump()'s virtual clock won't move it. runAsync sleeps the
    // real event loop while still letting the widget tree pump frames.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    await gesture.up();
    // pumpAndSettle can't be used — the mic orb runs continuous
    // pulse + wave animations that never settle. runAsync flushes
    // the real event loop so async chains (recorder.stop → apiCall
    // → setState → unawaited cleanup) resolve, then a discrete
    // pump rebuilds the tree with the new state.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('voice_status_error')), findsOneWidget);
    expect(find.textContaining('No se pudo procesar'), findsOneWidget);
  });

  testWidgets('API returning empty list shows the "no productos" error',
      (tester) async {
    final recorder = _FakeRecorder();
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: recorder,
      apiCall: ({required audioBytes, required mimeType, required filename}) async => [],
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('voice_mic_button'))));
    await tester.pump();
    // The recording-duration guard keys on DateTime.now() (real time),
    // so pump()'s virtual clock won't move it. runAsync sleeps the
    // real event loop while still letting the widget tree pump frames.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    await gesture.up();
    // pumpAndSettle can't be used — the mic orb runs continuous
    // pulse + wave animations that never settle. runAsync flushes
    // the real event loop so async chains (recorder.stop → apiCall
    // → setState → unawaited cleanup) resolve, then a discrete
    // pump rebuilds the tree with the new state.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('No identificamos productos'), findsOneWidget);
  });

  testWidgets('the API call receives the recorded audio as bytes',
      (tester) async {
    // Spec 020 / FR-03: the upload lambda is fed `Uint8List` + the real
    // MIME type, not a `dart:io File` — that is what lets the upload use
    // `MultipartFile.fromBytes` on web.
    Uint8List? receivedBytes;
    String? receivedMime;
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: _FakeRecorder(),
      apiCall: ({required audioBytes, required mimeType, required filename}) async {
        receivedBytes = audioBytes;
        receivedMime = mimeType;
        return [];
      },
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('voice_mic_button'))));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    await gesture.up();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(receivedBytes, isNotNull);
    expect(receivedBytes, equals(Uint8List.fromList(const [1, 2, 3, 4])));
    expect(receivedMime, 'audio/webm');
  });

  testWidgets('permission denied short-circuits into an error state',
      (tester) async {
    final recorder = _FakeRecorder(grantPermission: false);
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: recorder,
      apiCall: ({required audioBytes, required mimeType, required filename}) async => [],
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('voice_mic_button'))));
    await tester.pump();
    await gesture.up();
    // pumpAndSettle can't be used — the mic orb runs continuous
    // pulse + wave animations that never settle. runAsync flushes
    // the real event loop so async chains (recorder.stop → apiCall
    // → setState → unawaited cleanup) resolve, then a discrete
    // pump rebuilds the tree with the new state.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(recorder.started, isFalse,
        reason: 'Recorder.start must not fire when permission is denied');
    expect(find.byKey(const Key('voice_status_error')), findsOneWidget);
    expect(find.textContaining('Sin permiso'), findsOneWidget);
  });

  testWidgets('a throwing recorder lands on the error state, never mute',
      (tester) async {
    // Spec 020 / FR-04: any exception from the start path (here a
    // recorder whose `start` throws — the web symptom was `path_provider`
    // throwing) must surface a clear Spanish error, not a dead icon.
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: _ThrowingRecorder(),
      apiCall: ({required audioBytes, required mimeType, required filename}) async => [],
      resolvePath: _fakePath,
      readAudio: _fakeAudio,
    )));
    await tester.pump();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('voice_mic_button'))));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.byKey(const Key('voice_status_error')), findsOneWidget);
    expect(find.textContaining('No pudimos iniciar la grabación'),
        findsOneWidget);
  });
}
