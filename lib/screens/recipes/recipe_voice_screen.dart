// Spec: specs/065-recipe-studio/spec.md
//
// Dictado de receta por voz. Graba (cross-platform, reusando el facade de
// voice_recorder), manda el audio a /ai/voice-recipe y abre el Recipe Studio
// PRECARGADO para que el usuario revise/edite (nunca publica a ciegas).
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/voice_recorder.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import 'recipe_studio_screen.dart';

enum _VoiceState { idle, recording, processing, error }

class RecipeVoiceScreen extends StatefulWidget {
  final ApiService? api;
  final AudioRecorder? recorder;
  const RecipeVoiceScreen({super.key, this.api, this.recorder});

  @override
  State<RecipeVoiceScreen> createState() => _RecipeVoiceScreenState();
}

class _RecipeVoiceScreenState extends State<RecipeVoiceScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  late final AudioRecorder _recorder = widget.recorder ?? AudioRecorder();

  _VoiceState _state = _VoiceState.idle;
  String _message = '';

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() {
          _state = _VoiceState.error;
          _message = 'Necesitamos permiso del micrófono para dictar la receta.';
        });
        return;
      }
      final config = await resolveRecordConfig(_recorder);
      final path = await recordingPath();
      await _recorder.start(config, path: path);
      HapticFeedback.mediumImpact();
      setState(() {
        _state = _VoiceState.recording;
        _message = '';
      });
    } catch (e, st) {
      developer.log('No se pudo iniciar la grabación',
          name: 'RecipeVoiceScreen', error: e, stackTrace: st);
      setState(() {
        _state = _VoiceState.error;
        _message = 'No pudimos usar el micrófono. Intente de nuevo.';
      });
    }
  }

  Future<void> _stopAndSend() async {
    setState(() => _state = _VoiceState.processing);
    String? stopResult;
    try {
      stopResult = await _recorder.stop();
      if (stopResult == null || stopResult.isEmpty) {
        throw Exception('grabación vacía');
      }
      final audio = await readRecordedAudio(stopResult);
      final result = await _api.voiceRecipe(
        audioBytes: audio.bytes,
        mimeType: audio.mimeType,
        filename: audio.filename,
      );
      await disposeRecordedAudio(stopResult);
      if (!mounted) return;
      // Abre el Studio precargado, reemplazando esta pantalla.
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RecipeStudioScreen(initial: result),
      ));
    } on AppError catch (e) {
      if (stopResult != null) await disposeRecordedAudio(stopResult);
      if (!mounted) return;
      setState(() {
        _state = _VoiceState.error;
        _message = e.message;
      });
    } catch (e, st) {
      developer.log('Error al dictar receta',
          name: 'RecipeVoiceScreen', error: e, stackTrace: st);
      if (stopResult != null) await disposeRecordedAudio(stopResult);
      if (!mounted) return;
      setState(() {
        _state = _VoiceState.error;
        _message =
            'No pudimos interpretar el audio. Hable cerca del micrófono e intente de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _state == _VoiceState.recording;
    final processing = _state == _VoiceState.processing;
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Dictar receta', style: AppUI.title),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppUI.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  recording
                      ? 'Escuchando… diga el plato, los ingredientes y los pasos.'
                      : processing
                          ? 'Organizando su receta con IA…'
                          : 'Toque el micrófono y dicte su receta. La IA la arma '
                              'y usted la revisa antes de guardar.',
                  textAlign: TextAlign.center,
                  style: AppUI.bodySoft,
                ),
                const SizedBox(height: AppUI.s24),
                if (processing)
                  const CircularProgressIndicator()
                else
                  GestureDetector(
                    key: const Key('recipe_voice_mic'),
                    onTap: recording ? _stopAndSend : _start,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: recording ? AppTheme.error : AppTheme.primary,
                        boxShadow: AppUI.shadow,
                      ),
                      child: Icon(
                        recording ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: AppUI.s16),
                  Text(_message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.error)),
                ],
                const SizedBox(height: AppUI.s24),
                GhostButton(
                  icon: Icons.edit_rounded,
                  label: 'Mejor escribirla a mano',
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => const RecipeStudioScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
