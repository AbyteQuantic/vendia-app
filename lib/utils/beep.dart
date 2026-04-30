import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Play a loud cash-register beep + heavy vibration.
/// Used when a barcode scan finds a product match.
Future<void> playBeep() async {
  HapticFeedback.heavyImpact();
  final player = AudioPlayer();
  await player.setVolume(1.0);
  await player.play(AssetSource('audio/beep.wav'));
  // Dispose after playback completes
  player.onPlayerComplete.listen((_) => player.dispose());
}
