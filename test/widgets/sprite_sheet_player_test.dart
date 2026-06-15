// Spec: specs/048-onboarding-video-bg/spec.md
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/sprite_sheet_player.dart';

Future<ui.Image> fakeSheet() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 80, 50), Paint()..color = Colors.white);
  return recorder.endRecording().toImage(80, 50); // 8x5 de 10x10
}

void main() {
  group('frameIndexFor — ping-pong sin corte', () {
    test('arranca en 0 y avanza', () {
      expect(frameIndexFor(0, 40, true), 0);
      expect(frameIndexFor(5.9, 40, true), 5);
    });

    test('rebota en el último fotograma (N-1) y regresa', () {
      expect(frameIndexFor(39, 40, true), 39); // pico
      expect(frameIndexFor(40, 40, true), 38); // ya de regreso
      expect(frameIndexFor(41, 40, true), 37);
    });

    test('un período completo vuelve a 0 (loop continuo)', () {
      const period = 2 * (40 - 1); // 78
      expect(frameIndexFor(period.toDouble(), 40, true), 0);
    });

    test('índice siempre dentro de rango para muchas posiciones', () {
      for (var p = 0.0; p < 500; p += 0.37) {
        final i = frameIndexFor(p, 40, true);
        expect(i, inInclusiveRange(0, 39));
      }
    });

    test('modo loop simple (no ping-pong) hace módulo', () {
      expect(frameIndexFor(40, 40, false), 0);
      expect(frameIndexFor(41, 40, false), 1);
    });

    test('1 solo fotograma siempre devuelve 0', () {
      expect(frameIndexFor(123, 1, true), 0);
    });
  });

  testWidgets('SpriteSheetPlayer carga (loader inyectado) y pinta sin excepción',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 600,
          child: SpriteSheetPlayer(
            asset: 'fake',
            columns: 8,
            rows: 5,
            frameCount: 40,
            targetFps: 6,
            reduceMotion: true, // sin Ticker → test determinista
            imageLoader: (_) => fakeSheet(),
          ),
        ),
      ),
    ));
    await tester.pump(); // deja resolver el Future del loader
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con animación corre el Ticker sin romper', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 600,
          child: SpriteSheetPlayer(
            asset: 'fake',
            columns: 8,
            rows: 5,
            frameCount: 40,
            targetFps: 16,
            reduceMotion: false,
            imageLoader: (_) => fakeSheet(),
          ),
        ),
      ),
    ));
    await tester.pump(); // carga
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    // limpia el Ticker
    await tester.pumpWidget(const SizedBox());
  });
}
