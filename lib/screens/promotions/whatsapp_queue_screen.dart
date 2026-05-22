// Spec: specs/033-difusion-promociones/spec.md
//
// Cola de envío de WhatsApp en modo express (F033 — spec §4.5, AC-06).
//
// El dueño tiene N clientes seleccionados. WhatsApp prohíbe el
// auto-send, así que cada envío exige una acción del dueño. Lo que esta
// pantalla hace es volver esa acción "un solo botón con timer":
//
//   1. Banner inicial → botón "Empezar".
//   2. Para cada delivery: countdown 3s con animación visual y luego
//      auto-abre `wa.me/<phone>?text=<mensaje>` con el mensaje
//      pre-personalizado (sin que el dueño edite nada).
//   3. Cuando el dueño vuelve a la app (WidgetsBindingObserver detecta
//      `resumed`) el delivery se marca `sent` automáticamente y arranca
//      el countdown del siguiente.
//   4. Si el dueño no vuelve en 30s, la cola se auto-pausa — sin perder
//      progreso.
//   5. Botones siempre visibles: Pausar / Saltar / Reanudar.
//
// El mensaje de cada delivery ya viene pre-renderizado del backend
// (PromotionDelivery.renderedMessage). Como fallback defensivo, si
// llega vacío, se renderiza en el dispositivo con la plantilla de la
// promoción.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/broadcast_promotion.dart';
import '../../models/promotion_delivery.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/promotion_message_template.dart';

/// Segundos del countdown entre envíos (spec §4.5: 3s).
const int kQueueCountdownSeconds = 3;

/// Segundos sin retorno a la app tras los cuales la cola se auto-pausa.
const int kQueueIdleTimeoutSeconds = 30;

/// Estado de alto nivel de la cola.
enum QueuePhase {
  /// Banner inicial — esperando el "Empezar".
  intro,

  /// Countdown 3s antes de abrir el próximo chat.
  countdown,

  /// `wa.me` abierto — esperando que el dueño vuelva a la app.
  awaitingReturn,

  /// El dueño pausó (manual o por timeout de 30s).
  paused,

  /// Todos los deliveries procesados.
  done,
}

class WhatsappQueueScreen extends StatefulWidget {
  /// Promoción que se está difundiendo — su plantilla es el fallback
  /// de personalización cuando el delivery no trae mensaje pre-generado.
  final BroadcastPromotion promotion;

  /// Cola de envíos en estado `queued`.
  final List<PromotionDelivery> deliveries;

  /// Host del link público (ej. `https://tienda.vendia.store`).
  final String publicHost;

  /// Inyectable para tests.
  final ApiService? apiOverride;

  /// Inyectable para tests — abre la URL de WhatsApp. En producción usa
  /// `url_launcher`. Devuelve true si abrió.
  final Future<bool> Function(Uri uri)? launcherOverride;

  const WhatsappQueueScreen({
    super.key,
    required this.promotion,
    required this.deliveries,
    this.publicHost = 'https://tienda.vendia.store',
    this.apiOverride,
    this.launcherOverride,
  });

  @override
  State<WhatsappQueueScreen> createState() => _WhatsappQueueScreenState();
}

class _WhatsappQueueScreenState extends State<WhatsappQueueScreen>
    with WidgetsBindingObserver {
  late final ApiService _api;
  late List<PromotionDelivery> _deliveries;

  QueuePhase _phase = QueuePhase.intro;

  /// Índice del delivery actual en proceso.
  int _index = 0;

  /// Segundos restantes del countdown visible.
  int _countdown = kQueueCountdownSeconds;

  Timer? _countdownTimer;
  Timer? _idleTimer;

  /// True mientras el chat de WhatsApp está abierto — sirve para que el
  /// `didChangeAppLifecycleState` sepa que un `resumed` significa
  /// "el dueño volvió de enviar".
  bool _waitingForReturn = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _deliveries = List.of(widget.deliveries);
    WidgetsBinding.instance.addObserver(this);
    if (_deliveries.isEmpty) _phase = QueuePhase.done;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed && _waitingForReturn) {
      // El dueño volvió de WhatsApp → el delivery actual se considera
      // enviado y arrancamos el siguiente.
      _onReturnedFromWhatsApp();
    }
  }

  /// Cantidad de deliveries ya resueltos (sent o skipped).
  int get _resolvedCount => _deliveries
      .where((d) => d.status != PromotionDeliveryStatus.queued)
      .length;

  /// Mensaje a enviar para [d] — usa el pre-renderizado del backend o,
  /// como fallback, lo renderiza con la plantilla de la promoción.
  String _messageFor(PromotionDelivery d) {
    if (d.renderedMessage.trim().isNotEmpty) return d.renderedMessage;
    final base = widget.promotion.messageTemplate;
    final link = widget.promotion.publicUrl(widget.publicHost);
    final rendered = renderPromotionMessage(
      template: base,
      customerName: d.customerName,
    );
    return link.isEmpty ? rendered : '$rendered\n$link';
  }

  // ── Control de la cola ───────────────────────────────────────────

  void _start() {
    HapticFeedback.lightImpact();
    _beginCountdown();
  }

  void _beginCountdown() {
    _countdownTimer?.cancel();
    _idleTimer?.cancel();
    if (_index >= _deliveries.length) {
      setState(() => _phase = QueuePhase.done);
      return;
    }
    setState(() {
      _phase = QueuePhase.countdown;
      _countdown = kQueueCountdownSeconds;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown <= 1) {
        t.cancel();
        _openWhatsApp();
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _openWhatsApp() async {
    if (_index >= _deliveries.length) {
      setState(() => _phase = QueuePhase.done);
      return;
    }
    final delivery = _deliveries[_index];
    final phone = _normalizePhone(delivery.customerPhone);
    final text = Uri.encodeComponent(_messageFor(delivery));
    final uri = phone.isEmpty
        ? Uri.parse('https://wa.me/?text=$text')
        : Uri.parse('https://wa.me/$phone?text=$text');

    setState(() {
      _phase = QueuePhase.awaitingReturn;
      _waitingForReturn = true;
    });

    // Si el dueño no vuelve en 30s, la cola se auto-pausa (spec §4.5).
    _idleTimer?.cancel();
    _idleTimer = Timer(
      const Duration(seconds: kQueueIdleTimeoutSeconds),
      _onIdleTimeout,
    );

    final launcher = widget.launcherOverride ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final ok = await launcher(uri);
    if (!ok && mounted) {
      _snack('No se pudo abrir WhatsApp. Toque "Reintentar".');
      _idleTimer?.cancel();
      setState(() {
        _phase = QueuePhase.paused;
        _waitingForReturn = false;
      });
    }
  }

  /// El dueño volvió a la app — marcamos `sent` y seguimos.
  Future<void> _onReturnedFromWhatsApp() async {
    _idleTimer?.cancel();
    _waitingForReturn = false;
    await _markCurrent(PromotionDeliveryStatus.sent);
    _advance();
  }

  void _onIdleTimeout() {
    if (!mounted) return;
    _waitingForReturn = false;
    setState(() => _phase = QueuePhase.paused);
    _snack('Pausamos la cola — su progreso está guardado.');
  }

  /// Marca el delivery actual con [status] en el backend y en memoria.
  Future<void> _markCurrent(PromotionDeliveryStatus status) async {
    if (_index >= _deliveries.length) return;
    final delivery = _deliveries[_index];
    setState(() {
      _deliveries[_index] = delivery.copyWith(
        status: status,
        sentAt: status == PromotionDeliveryStatus.sent
            ? DateTime.now()
            : null,
      );
    });
    try {
      await _api.updatePromotionDelivery(
        widget.promotion.id,
        delivery.id,
        status: status.wire,
      );
    } catch (_) {
      // El estado local ya cambió; un fallo de red no debe trabar la
      // cola — el backend se reconcilia en el próximo fetch del detalle.
    }
  }

  /// Pasa al siguiente delivery `queued`.
  void _advance() {
    var next = _index + 1;
    while (next < _deliveries.length &&
        _deliveries[next].status != PromotionDeliveryStatus.queued) {
      next++;
    }
    _index = next;
    if (_index >= _deliveries.length) {
      _countdownTimer?.cancel();
      _idleTimer?.cancel();
      setState(() => _phase = QueuePhase.done);
    } else {
      _beginCountdown();
    }
  }

  void _pause() {
    HapticFeedback.lightImpact();
    _countdownTimer?.cancel();
    _idleTimer?.cancel();
    _waitingForReturn = false;
    setState(() => _phase = QueuePhase.paused);
  }

  void _resume() {
    HapticFeedback.lightImpact();
    _beginCountdown();
  }

  Future<void> _skip() async {
    HapticFeedback.lightImpact();
    _countdownTimer?.cancel();
    _idleTimer?.cancel();
    _waitingForReturn = false;
    await _markCurrent(PromotionDeliveryStatus.skipped);
    _advance();
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    // Número colombiano de 10 dígitos → anteponer el indicativo 57.
    if (digits.length == 10) return '57$digits';
    return digits;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Text(
          'Enviar por WhatsApp',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_phase) {
            QueuePhase.intro => _buildIntro(),
            QueuePhase.done => _buildDone(),
            _ => _buildRunning(),
          },
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.chat_rounded,
                      color: Color(0xFF25D366), size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Modo express',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'VendIA va a abrir un chat de WhatsApp cada '
                '$kQueueCountdownSeconds segundos. El mensaje ya está '
                'listo y personalizado — solo toque "Enviar" en '
                'WhatsApp y vuelva a esta pantalla.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${_deliveries.length} ${_deliveries.length == 1 ? 'cliente' : 'clientes'} en la cola',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            key: const Key('queue_start_button'),
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: const Text(
              'Empezar',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    final sent = _deliveries
        .where((d) => d.status == PromotionDeliveryStatus.sent)
        .length;
    final skipped = _deliveries
        .where((d) => d.status == PromotionDeliveryStatus.skipped)
        .length;
    return Column(
      key: const Key('queue_done'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_rounded,
            size: 72, color: AppTheme.success),
        const SizedBox(height: 16),
        const Text(
          '¡Cola terminada!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enviados: $sent · Omitidos: $skipped',
          style: const TextStyle(
            fontSize: 17,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            key: const Key('queue_finish_button'),
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Listo',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    final delivery =
        _index < _deliveries.length ? _deliveries[_index] : null;
    final total = _deliveries.length;
    final progress = total == 0 ? 0.0 : _resolvedCount / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progreso global de la cola. El "actual" es 1-indexado: el
        // delivery en curso cuenta como el N-ésimo de la cola.
        Row(
          children: [
            Text(
              '🟢 ${(_index + 1).clamp(1, total)} de $total',
              key: const Key('queue_progress_label'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            if (_phase == QueuePhase.paused)
              const Text(
                'En pausa',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.warning,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: AppTheme.borderColor,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(height: 24),
        if (delivery != null)
          Expanded(child: _buildCurrentCard(delivery)),
        _buildControls(),
      ],
    );
  }

  Widget _buildCurrentCard(PromotionDelivery delivery) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_rounded,
                    color: AppTheme.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    delivery.customerName.isNotEmpty
                        ? delivery.customerName
                        : 'Cliente sin nombre',
                    key: const Key('queue_customer_name'),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // El countdown grande y visible (spec §4.5).
            if (_phase == QueuePhase.countdown)
              Center(
                child: Column(
                  children: [
                    Text(
                      '$_countdown',
                      key: const Key('queue_countdown'),
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF25D366),
                      ),
                    ),
                    const Text(
                      'Abriendo WhatsApp…',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            if (_phase == QueuePhase.awaitingReturn)
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 48, color: Color(0xFF25D366)),
                    SizedBox(height: 8),
                    Text(
                      'Toque "Enviar" en WhatsApp\ny vuelva a esta '
                      'pantalla',
                      key: Key('queue_awaiting_return'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              'Mensaje',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Text(
                _messageFor(delivery),
                key: const Key('queue_message_preview'),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final isPaused = _phase == QueuePhase.paused;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                key: const Key('queue_skip_button'),
                onPressed: _skip,
                icon: const Icon(Icons.skip_next_rounded, size: 22),
                label: const Text(
                  'Saltar',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: const BorderSide(color: AppTheme.borderColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                key: Key(
                    isPaused ? 'queue_resume_button' : 'queue_pause_button'),
                onPressed: isPaused ? _resume : _pause,
                icon: Icon(
                  isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  size: 22,
                ),
                label: Text(
                  isPaused ? 'Reanudar' : 'Pausar',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isPaused ? AppTheme.success : AppTheme.warning,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
