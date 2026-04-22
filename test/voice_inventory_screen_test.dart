import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:vendia_pos/screens/inventory/voice_inventory_screen.dart';

/// Widget tests for the Phase-4 Voice Inventory screen.
///
/// The screen has two external collaborators:
///   1. An AudioRecorder — we inject a fake that satisfies the
///      ~4 methods the widget actually calls (`hasPermission`,
///      `start`, `stop`, `dispose`).
///   2. An API call — we inject a VoiceApiCall lambda so the tests
///      can simulate the happy path + empty-result path.
///
/// The mic orb is activated via a GestureDetector whose onTapDown +
/// onTapUp fire synchronously with `tester.press`/`releasePointer`,
/// letting us exercise the state machine without a long-press
/// simulation library.

class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({
    this.grantPermission = true,
    this.stopPath = '/tmp/fake.m4a',
  });

  final bool grantPermission;
  String? stopPath;

  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => grantPermission;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    started = true;
    stopPath = path;
  }

  @override
  Future<String?> stop() async {
    stopped = true;
    return stopPath;
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

Future<Directory> _tempDir() async => Directory.systemTemp;

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initial state renders mic orb + "mantén presionado" hint',
      (tester) async {
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: _FakeRecorder(),
      apiCall: ({required audioFile, required mimeType}) async => [],
      resolveTempDir: _tempDir,
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
      apiCall: ({required audioFile, required mimeType}) async => [],
      resolveTempDir: _tempDir,
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
      apiCall: ({required audioFile, required mimeType}) async {
        apiCalls++;
        return [];
      },
      resolveTempDir: _tempDir,
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
    // → setState → unawaited File.delete) resolve, then a discrete
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
      apiCall: ({required audioFile, required mimeType}) async {
        throw Exception('boom');
      },
      resolveTempDir: _tempDir,
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
    // → setState → unawaited File.delete) resolve, then a discrete
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
      apiCall: ({required audioFile, required mimeType}) async => [],
      resolveTempDir: _tempDir,
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
    // → setState → unawaited File.delete) resolve, then a discrete
    // pump rebuilds the tree with the new state.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('No identificamos productos'), findsOneWidget);
  });

  testWidgets('permission denied short-circuits into an error state',
      (tester) async {
    final recorder = _FakeRecorder(grantPermission: false);
    await tester.pumpWidget(_wrap(VoiceInventoryScreen(
      recorder: recorder,
      apiCall: ({required audioFile, required mimeType}) async => [],
      resolveTempDir: _tempDir,
    )));
    await tester.pump();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('voice_mic_button'))));
    await tester.pump();
    await gesture.up();
    // pumpAndSettle can't be used — the mic orb runs continuous
    // pulse + wave animations that never settle. runAsync flushes
    // the real event loop so async chains (recorder.stop → apiCall
    // → setState → unawaited File.delete) resolve, then a discrete
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
}
