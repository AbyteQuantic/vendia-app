// Spec: specs/020-voz-inventario-web/spec.md
//
// Phase-4 "Killer feature": Voice-to-Catalog. Spec 020 made this screen
// cross-platform: the recording path no longer depends on `dart:io` /
// `path_provider`, so it works on Flutter web (`vendia.store`) too.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/voice_recorder.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/premium_upsell_sheet.dart';
import 'ia_result_screen.dart';

/// Phase-4 "Killer feature": Voice-to-Catalog.
///
/// UX: press-and-hold the mic to dictate products; release to send
/// the audio to Gemini. A Lottie-esque loader takes over while the
/// server parses, and the result lands on the existing IaResultScreen
/// so the tendero reviews + edits + saves with the same muscle memory
/// as the OCR flow.
///
/// Spec 020: the audio is captured cross-platform — m4a on mobile,
/// WebM/Opus on web — and handed to the API layer as raw BYTES, so the
/// upload uses `MultipartFile.fromBytes` and never touches a filesystem.
///
/// The screen accepts injectable [recorder], [apiCall], [resolvePath]
/// and [readAudio] so widget tests can exercise press/release behavior
/// without touching the microphone, `path_provider` or the network.
typedef VoiceApiCall = Future<List<Map<String, dynamic>>> Function({
  required Uint8List audioBytes,
  required String mimeType,
  required String filename,
});

/// Resolves the path passed to [AudioRecorder.start]. Defaults to the
/// cross-platform [recordingPath] (temp dir on mobile, ignored on web).
typedef VoiceResolvePath = Future<String> Function();

/// Turns the value returned by [AudioRecorder.stop] into upload-ready
/// bytes. Defaults to the cross-platform [readRecordedAudio].
typedef VoiceReadAudio = Future<RecordedAudio> Function(String stopResult);

class VoiceInventoryScreen extends StatefulWidget {
  const VoiceInventoryScreen({
    super.key,
    AudioRecorder? recorder,
    VoiceApiCall? apiCall,
    VoiceResolvePath? resolvePath,
    VoiceReadAudio? readAudio,
  })  : _recorder = recorder,
        _apiCall = apiCall,
        _resolvePath = resolvePath,
        _readAudio = readAudio;

  final AudioRecorder? _recorder;
  final VoiceApiCall? _apiCall;
  final VoiceResolvePath? _resolvePath;
  final VoiceReadAudio? _readAudio;

  @override
  State<VoiceInventoryScreen> createState() => _VoiceInventoryScreenState();
}

enum _VoiceStatus { idle, recording, processing, error }

class _VoiceInventoryScreenState extends State<VoiceInventoryScreen>
    with TickerProviderStateMixin {
  late final AudioRecorder _recorder;
  late final VoiceApiCall _apiCall;
  late final VoiceResolvePath _resolvePath;
  late final VoiceReadAudio _readAudio;

  late final AnimationController _pulseCtrl;
  late final AnimationController _wavesCtrl;

  _VoiceStatus _status = _VoiceStatus.idle;
  DateTime? _recordingStartedAt;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  String? _errorMessage;

  // Cap the clip at 90s so a forgotten-finger-on-button doesn't upload
  // a 20-minute recording and burn Gemini tokens. The backend accepts
  // up to ~60s comfortably; a little headroom is fine.
  static const Duration _maxDuration = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _recorder = widget._recorder ?? AudioRecorder();
    _apiCall = widget._apiCall ?? _defaultApiCall;
    _resolvePath = widget._resolvePath ?? recordingPath;
    _readAudio = widget._readAudio ?? readRecordedAudio;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _wavesCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  Future<List<Map<String, dynamic>>> _defaultApiCall({
    required Uint8List audioBytes,
    required String mimeType,
    required String filename,
  }) {
    return ApiService(AuthService()).voiceInventory(
      audioBytes: audioBytes,
      mimeType: mimeType,
      filename: filename,
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _pulseCtrl.dispose();
    _wavesCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startRecording() async {
    if (_status != _VoiceStatus.idle && _status != _VoiceStatus.error) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Spec 020 / FR-04: the WHOLE start path is guarded. A denied mic
    // permission, a browser without MediaRecorder support, or any
    // exception from `record` must land on a clear Spanish error — the
    // mic icon never stays mute and never throws unhandled. (The old
    // code threw on web here because `path_provider` has no web impl.)
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _status = _VoiceStatus.error;
          _errorMessage =
              'Sin permiso para usar el micrófono. Actívalo en los '
              'ajustes del navegador o del teléfono.';
        });
        return;
      }

      // On mobile this is a temp-dir file path; on web `record` ignores
      // it (the clip lives in browser memory as a blob). Either way no
      // `path_provider` call ever runs on the web build.
      final path = await _resolvePath();

      // Negocia el encoder en runtime: opus en Chrome/Android, mp4/AAC en
      // Safari/iOS, WAV como último recurso universal. Antes se forzaba
      // opus → en iPhone `start()` lanzaba "encoder not supported" y el
      // micrófono parecía no hacer nada.
      final config = await resolveRecordConfig(_recorder);
      await _recorder.start(config, path: path);

      if (!mounted) return;
      setState(() {
        _status = _VoiceStatus.recording;
        _recordingStartedAt = DateTime.now();
        _elapsed = Duration.zero;
        _errorMessage = null;
      });

      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_recordingStartedAt == null) return;
        final now = DateTime.now();
        if (!mounted) return;
        setState(() => _elapsed = now.difference(_recordingStartedAt!));
        if (_elapsed >= _maxDuration) {
          _stopAndSend();
        }
      });
    } catch (e, stack) {
      debugPrint('[VOICE] start recording failed: $e\n$stack');
      _elapsedTimer?.cancel();
      _recordingStartedAt = null;
      if (!mounted) return;
      setState(() {
        _status = _VoiceStatus.error;
        _errorMessage =
            'No pudimos iniciar la grabación. Revisa el permiso del '
            'micrófono e intenta otra vez.';
      });
    }
  }

  Future<void> _stopAndSend() async {
    if (_status != _VoiceStatus.recording) return;
    _elapsedTimer?.cancel();
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    // `stop()` returns a filesystem path on mobile and a blob URL on
    // web — `_recorder.stop` itself is cross-platform; we only branch
    // when turning that result into bytes (see `readRecordedAudio`).
    String? stopResult;
    try {
      stopResult = await _recorder.stop();
    } catch (e, stack) {
      debugPrint('[VOICE] stop recording failed: $e\n$stack');
      stopResult = null;
    }
    if (stopResult == null) {
      if (!mounted) return;
      setState(() {
        _status = _VoiceStatus.error;
        _errorMessage = 'No se pudo guardar el audio. Intenta otra vez.';
      });
      return;
    }
    final String result = stopResult;

    // Require a minimum duration so the user doesn't waste an API
    // round-trip on a 200 ms tap. Use real-clock elapsed (not the
    // _elapsed state field) because _elapsed ticks on the widget
    // test's virtual clock, which doesn't advance during runAsync —
    // that would cause deterministic tests to mis-fire the guard.
    final realElapsed = _recordingStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_recordingStartedAt!);
    if (realElapsed.inMilliseconds < 1200) {
      if (!mounted) return;
      setState(() {
        _status = _VoiceStatus.error;
        _errorMessage =
            'Grabación muy corta. Mantén presionado mientras dictas los productos.';
      });
      unawaited(disposeRecordedAudio(result));
      return;
    }

    setState(() => _status = _VoiceStatus.processing);

    // Read the recorded clip as bytes — `dart:io` on mobile, a blob
    // fetch on web. The architecture records audio + ships straight to
    // Gemini multimodal (no on-device STT), so there is no transcript
    // to log here; the backend logs the raw Gemini response when the
    // extracted items look wrong.
    final RecordedAudio audio;
    try {
      audio = await _readAudio(result);
    } catch (e, stack) {
      debugPrint('[VOICE] reading recorded audio failed: $e\n$stack');
      unawaited(disposeRecordedAudio(result));
      if (!mounted) return;
      setState(() {
        _status = _VoiceStatus.error;
        _errorMessage = 'No se pudo leer el audio grabado. Intenta otra vez.';
      });
      return;
    }
    debugPrint(
        '[VOICE] uploading audio duration=${realElapsed.inMilliseconds}ms '
        'size=${audio.bytes.length}B type=${audio.mimeType}');

    try {
      final items = await _apiCall(
        audioBytes: audio.bytes,
        mimeType: audio.mimeType,
        filename: audio.filename,
      );
      debugPrint(
          '[VOICE] extracted ${items.length} items: '
          '${items.map((i) => '${i['quantity']}x ${i['name']}').join(', ')}');
      if (!mounted) return;
      if (items.isEmpty) {
        setState(() {
          _status = _VoiceStatus.error;
          _errorMessage =
              'No identificamos productos. Menciona nombre, cantidad y precio.';
        });
        return;
      }
      _navigateToReview(items);
    } catch (e, stack) {
      // Paywall short-circuit: when the backend says this tenant
      // isn't entitled to AI features we route to the soft paywall
      // sheet INSTEAD of the red error banner. The Dio interceptor
      // already fires PremiumUpsellController.notifyBlocked() on
      // any 403 with the structured code — we also invoke it from
      // here to cover the direct `showPremiumUpsellSheet` path in
      // case the controller isn't wired yet (e.g. during tests
      // that instantiate the screen with an injected apiCall).
      debugPrint('[VOICE] inventory call failed: $e\n$stack');
      if (!mounted) return;
      if (e is AppError && e.isPremiumLocked) {
        setState(() {
          _status = _VoiceStatus.idle;
          _errorMessage = null;
        });
        unawaited(showPremiumUpsellSheet(
          context,
          reason:
              'La dictación por voz es una función PRO. Actívala para seguir usándola.',
        ));
      } else {
        final friendly = _friendlyMessageFor(e);
        setState(() {
          _status = _VoiceStatus.error;
          _errorMessage = friendly;
        });
        // Only surface an extra SnackBar for actionable network /
        // auth errors — the inline status banner already covers the
        // generic case. Avoids double-showing the same copy.
        final shouldToast = e is AppError &&
            (e.type == AppErrorType.network ||
                e.type == AppErrorType.server);
        if (shouldToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('voice_error_snackbar'),
              content: Text(friendly),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } finally {
      // Fire-and-forget the cleanup so the state transition above is
      // visible to the framework without waiting on I/O — matters for
      // widget tests where the fake path doesn't exist, but production
      // benefits too: the user sees the result/error instantly instead
      // of after a disk op (mobile) or a blob revoke (web).
      unawaited(disposeRecordedAudio(result));
    }
  }

  /// Translate the raw error into a single-sentence Spanish message
  /// the tendero can actually act on. Premium-lock errors never
  /// reach this helper — they're handled above via the paywall
  /// sheet, so the `auth` branch here only fires for 401 (token
  /// expired) and other 403s without the paywall payload.
  String _friendlyMessageFor(Object e) {
    if (e is AppError) {
      switch (e.type) {
        case AppErrorType.network:
          return 'Sin conexión estable. Revisa el internet e intenta otra vez.';
        case AppErrorType.auth:
          if (e.statusCode == 401) {
            return 'Tu sesión expiró. Vuelve a iniciar sesión para dictar productos.';
          }
          return e.message;
        case AppErrorType.validation:
          return e.message;
        case AppErrorType.server:
          return 'El servidor no pudo interpretar el audio: ${e.message}';
        case AppErrorType.unknown:
          return e.message;
      }
    }
    return 'No se pudo procesar: $e';
  }

  void _navigateToReview(List<Map<String, dynamic>> items) {
    // IaResultScreen reads `unit_price` whereas the voice payload
    // carries `price`. Mapping here keeps the OCR contract intact —
    // the review UI doesn't have to know a new source exists.
    final mapped = items
        .map((raw) => {
              'name': raw['name'] ?? '',
              'quantity': raw['quantity'] ?? 0,
              'unit_price': (raw['price'] as num?)?.toDouble() ?? 0,
              'total_price': ((raw['price'] as num?)?.toDouble() ?? 0) *
                  ((raw['quantity'] as num?)?.toInt() ?? 0),
              'confidence': 0.85,
            })
        .toList();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => IaResultScreen(
          extractedProducts: mapped,
          providerName: 'Dictado por voz',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Inventario por Voz',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Text(
                'Mantén presionado el micrófono y dicta los productos que llegaron.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ejemplo: "Llegaron 12 cocas de 350, 20 panes Bimbo a 3.500, 5 aceites Girasol"',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const Spacer(),
              _MicOrb(
                status: _status,
                elapsed: _elapsed,
                pulse: _pulseCtrl,
                waves: _wavesCtrl,
                onPressStart: _startRecording,
                onPressEnd: _stopAndSend,
              ),
              const SizedBox(height: 16),
              _StatusText(
                status: _status,
                elapsed: _elapsed,
                errorMessage: _errorMessage,
                fmt: _fmt,
              ),
              const Spacer(),
              if (_status == _VoiceStatus.processing)
                const _IAThinkingRow(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicOrb extends StatelessWidget {
  const _MicOrb({
    required this.status,
    required this.elapsed,
    required this.pulse,
    required this.waves,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final _VoiceStatus status;
  final Duration elapsed;
  final AnimationController pulse;
  final AnimationController waves;
  final Future<void> Function() onPressStart;
  final Future<void> Function() onPressEnd;

  @override
  Widget build(BuildContext context) {
    final isRecording = status == _VoiceStatus.recording;
    final isBusy = status == _VoiceStatus.processing;

    return GestureDetector(
      key: const Key('voice_mic_button'),
      // Single-detector press-and-hold: onTapDown fires immediately
      // on pointer down (no tap-vs-long-press arena to win), and
      // onTapUp / onTapCancel cover both release and pointer-cancel.
      // Adding onLongPress* would swallow onTapDown until the
      // long-press timer fires, so we deliberately stick to tap
      // callbacks only.
      onTapDown: isBusy || isRecording ? null : (_) => onPressStart(),
      onTapUp: isBusy ? null : (_) => onPressEnd(),
      onTapCancel: isBusy ? null : () => onPressEnd(),
      child: AnimatedBuilder(
        animation: Listenable.merge([pulse, waves]),
        builder: (context, _) {
          final scale = isRecording ? 1.0 + (pulse.value * 0.12) : 1.0;
          return SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isRecording) ..._buildWaveRipples(),
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isRecording
                            ? const [Color(0xFFEF4444), Color(0xFFDC2626)]
                            : const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isRecording
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF2563EB))
                              .withValues(alpha: 0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    // During processing the orb morphs into a spinner
                    // so the tendero gets unmistakable "working" feedback
                    // and doesn't keep tapping. Recording / idle keep
                    // the microphone icon.
                    child: Center(
                      child: isBusy
                          ? const SizedBox(
                              key: Key('voice_mic_spinner'),
                              width: 54,
                              height: 54,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.mic_rounded,
                              color: Colors.white,
                              size: 64,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildWaveRipples() {
    return List.generate(3, (i) {
      final t = (waves.value + i / 3) % 1.0;
      final scale = 0.9 + t * 1.2;
      final opacity = (1 - t).clamp(0.0, 1.0) * 0.4;
      return IgnorePointer(
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEF4444).withValues(alpha: opacity),
            ),
          ),
        ),
      );
    });
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({
    required this.status,
    required this.elapsed,
    required this.errorMessage,
    required this.fmt,
  });

  final _VoiceStatus status;
  final Duration elapsed;
  final String? errorMessage;
  final String Function(Duration) fmt;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _VoiceStatus.recording:
        return Text(
          'Grabando… ${fmt(elapsed)}',
          key: const Key('voice_status_recording'),
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDC2626)),
        );
      case _VoiceStatus.processing:
        return const Text(
          'IA pensando…',
          key: Key('voice_status_processing'),
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary),
        );
      case _VoiceStatus.error:
        return Text(
          errorMessage ?? 'Algo salió mal. Intenta otra vez.',
          key: const Key('voice_status_error'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.error),
        );
      case _VoiceStatus.idle:
        return const Text(
          'Mantén presionado para grabar',
          key: Key('voice_status_idle'),
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        );
    }
  }
}

class _IAThinkingRow extends StatelessWidget {
  const _IAThinkingRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Text(
          'Procesando con Gemini (~${math.max(3, _ProcessingEta._seconds)}s)',
          style:
              const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

// Separate holder so the ETA constant lives as a named value rather
// than a magic number scattered in the widget tree.
class _ProcessingEta {
  static const int _seconds = 8;
}
