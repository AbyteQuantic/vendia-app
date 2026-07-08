// Spec: specs/101-retocar-fotos-inventario/spec.md
//
// "Retocar fotos": recorre las referencias con foto propia CRUDA (sin pasar
// por Mejorar con IA) y las deja presentables. TODO retoque pasa por la cola
// del backend (veredicto del concilio D1/D5 + corrección de diseño):
// "Mejorar foto" individual encola un LOTE DE 1 (POST /retouch/batches);
// "Retocar todas (N)" encola el lote completo tras confirmar el número. El
// worker guarda el resultado en candidate_url SIN tocar el producto; los
// ítems llegan como review_items del summary y aparecen ARRIBA con
// antes/después para Confirmar/Descartar (nada se aplica solo — FR-05).
// El progreso se consulta con polling suave (5-10s con backoff, patrón
// Spec 016) y una pausa del lote (cuota de IA) se muestra en calma, sin la
// palabra "error" ni botón de reintento: la cola reanuda sola (AC-10).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/retouch_cards.dart';

/// Estado mutable por producto pendiente (patrón _Row de Spec 097/100).
class _Row {
  _Row(this.product);
  final Map<String, dynamic> product;

  bool busy = false; // encolando (red en vuelo)
  bool queued = false; // ya dentro de un lote activo
  bool done = false; // retoque confirmado: no vuelve a la lista

  String get id => (product['id'] ?? product['uuid'] ?? '').toString();
  String get name => (product['name'] ?? '').toString();
  double get price => (product['price'] as num?)?.toDouble() ?? 0;

  String? get photoUrl {
    final photo = (product['photo_url'] as String? ?? '').trim();
    final image = (product['image_url'] as String? ?? '').trim();
    final v = photo.isNotEmpty ? photo : image;
    return v.isEmpty ? null : v;
  }
}

/// Ítem del lote listo para revisar (antes/después) — viene del summary.
class _ReviewItem {
  _ReviewItem({
    required this.itemId,
    required this.productId,
    required this.name,
    required this.originalUrl,
    required this.candidateUrl,
  });

  factory _ReviewItem.fromJson(Map<String, dynamic> json) => _ReviewItem(
        itemId: (json['item_id'] ?? '').toString(),
        productId: (json['product_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        originalUrl: (json['original_url'] ?? '').toString(),
        candidateUrl: (json['candidate_url'] ?? '').toString(),
      );

  final String itemId;
  final String productId;
  final String name;
  final String originalUrl;
  final String candidateUrl;

  bool busy = false;
  bool leaving = false; // confirmada/descartada: sale con animación
}

/// Acción fallida por red, pendiente de reintento manual (el contador nunca
/// miente: nada se marca hecho sin confirmación del servidor).
class _PendingRetry {
  const _PendingRetry(this.message, this.action);
  final String message;
  final Future<void> Function() action;
}

class RetouchCompletionScreen extends StatefulWidget {
  const RetouchCompletionScreen({
    super.key,
    required this.products,
    @visibleForTesting this.apiOverride,
    @visibleForTesting this.pollInterval = const Duration(seconds: 6),
  });

  /// Referencias con foto sin retocar (mapas crudos del backend), ya
  /// prefiltradas por Mi Inventario con [isPhotoUnretouched] (FR-03/FR-09).
  final List<Map<String, dynamic>> products;

  @visibleForTesting
  final ApiService? apiOverride;

  /// Intervalo base del polling del summary (FR-14). Inyectable en pruebas.
  @visibleForTesting
  final Duration pollInterval;

  @override
  State<RetouchCompletionScreen> createState() =>
      _RetouchCompletionScreenState();
}

class _RetouchCompletionScreenState extends State<RetouchCompletionScreen> {
  late final ApiService _api;
  late final List<_Row> _rows;

  final List<_ReviewItem> _review = [];

  /// Ítems ya confirmados/descartados en esta sesión: el siguiente poll del
  /// summary no debe re-pintarlos aunque el backend aún los liste.
  final Set<String> _handledItemIds = {};

  Map<String, dynamic>? _batch; // lote activo (running | paused_error)
  _PendingRetry? _retry;
  Timer? _pollTimer;
  int _pollFailures = 0;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _rows = widget.products.map(_Row.new).toList();
    // AC-09: un lote encolado en otra sesión/dispositivo se retoma al abrir.
    _refreshSummary();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Datos derivados ────────────────────────────────────────────────────────

  bool _inReview(String productId) =>
      _review.any((i) => !i.leaving && i.productId == productId);

  List<_Row> get _pendingRows =>
      _rows.where((r) => !r.done && !_inReview(r.id)).toList();

  List<_Row> get _idleRows =>
      _pendingRows.where((r) => !r.queued && !r.busy).toList();

  List<_ReviewItem> get _reviewables =>
      _review.where((i) => !i.leaving && !i.busy).toList();

  int get _doneCount => _rows.where((r) => r.done).length;

  bool get _allDone =>
      _pendingRows.isEmpty && _review.isEmpty && _batch == null;

  String? get _batchStatus => (_batch?['status'] as String?)?.trim();

  // ── Summary + polling (FR-14, patrón Spec 016) ─────────────────────────────

  Future<void> _refreshSummary() async {
    Map<String, dynamic> summary;
    try {
      summary = await _api.fetchRetouchSummary();
    } on AppError {
      // El progreso es informativo: un poll fallido no interrumpe al tendero
      // con un banner; el siguiente intento llega con backoff.
      if (!mounted) return;
      _pollFailures++;
      _scheduleNextPoll();
      return;
    } catch (_) {
      if (!mounted) return;
      _pollFailures++;
      _scheduleNextPoll();
      return;
    }
    if (!mounted) return;
    _pollFailures = 0;
    setState(() => _applySummary(summary));
    _scheduleNextPoll();
  }

  void _applySummary(Map<String, dynamic> summary) {
    final rawBatch = summary['active_batch'];
    final batch = rawBatch is Map ? rawBatch.cast<String, dynamic>() : null;
    final status = (batch?['status'] as String?)?.trim() ?? '';
    // Solo un lote vivo pinta banner y polling; completado/cancelado ya no.
    _batch =
        (status == 'running' || status == 'paused_error') ? batch : null;
    if (_batch == null) {
      for (final r in _rows) {
        r.queued = false;
      }
    }

    final rawItems = (summary['review_items'] as List?) ?? const [];
    final serverItems = rawItems
        .whereType<Map>()
        .map((m) => _ReviewItem.fromJson(m.cast<String, dynamic>()))
        .where((i) => i.itemId.isNotEmpty)
        .where((i) => !_handledItemIds.contains(i.itemId))
        .toList();
    // Conserva el estado local (busy/leaving) de los ya pintados; los nuevos
    // aparecen arriba a medida que el worker los deja listos.
    final existingIds = _review.map((i) => i.itemId).toSet();
    final fresh =
        serverItems.where((i) => !existingIds.contains(i.itemId)).toList();
    final serverIds = serverItems.map((i) => i.itemId).toSet();
    _review.removeWhere((i) =>
        !i.leaving && !i.busy && !serverIds.contains(i.itemId));
    _review.insertAll(0, fresh);
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    if (!mounted || _batch == null) return;
    // Backoff suave: 1x → 2x → 4x el intervalo base, con tope de 60 s.
    final base = widget.pollInterval;
    final factor = 1 << _pollFailures.clamp(0, 3);
    var next = base * factor;
    if (next > const Duration(seconds: 60)) {
      next = const Duration(seconds: 60);
    }
    _pollTimer = Timer(next, _refreshSummary);
  }

  // ── Encolar (FR-11; corrección de diseño: TODO pasa por el lote) ──────────

  /// "Mejorar foto" de UNA tarjeta = lote de 1: mismo camino fiel del
  /// backend, misma revisión antes/después; nada se aplica sin confirmar.
  Future<void> _retouchOne(_Row row) async {
    if (row.busy || row.queued) return;
    HapticFeedback.lightImpact();
    await _enqueue([row]);
  }

  Future<void> _retouchAll() async {
    final pending = _idleRows;
    if (pending.isEmpty) return;
    HapticFeedback.lightImpact();
    final confirmed = await _confirmSheet(
      title: '¿Retocar todas las fotos?',
      body: 'La IA mejorará ${pending.length} fotos en segundo plano, una '
          'por una. Puede cerrar la aplicación: aquí verá el avance y nada '
          'cambia hasta que usted confirme cada foto.',
      confirmLabel: 'Retocar ${pending.length} fotos',
    );
    if (confirmed != true || !mounted) return;
    await _enqueue(pending);
  }

  Future<void> _enqueue(List<_Row> rows) async {
    setState(() {
      for (final r in rows) {
        r.busy = true;
      }
      _retry = null;
    });
    try {
      final result =
          await _api.createRetouchBatch(productIds: rows.map((r) => r.id).toList());
      if (!mounted) return;
      final skipped = ((result['skipped'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => (m['product_id'] ?? '').toString())
          .toSet();
      setState(() {
        for (final r in rows) {
          r.busy = false;
          r.queued = !skipped.contains(r.id);
        }
      });
      // Refresco inmediato: si el lote de 1 ya quedó listo, la revisión
      // aparece sin esperar el primer tick del polling.
      await _refreshSummary();
    } on AppError catch (e) {
      if (!mounted) return;
      _failEnqueue(rows, e);
    } catch (_) {
      if (!mounted) return;
      _failEnqueue(
          rows,
          const AppError(
              type: AppErrorType.unknown,
              message: 'Algo salió mal. Intente de nuevo.'));
    }
  }

  void _failEnqueue(List<_Row> rows, AppError e) {
    HapticFeedback.heavyImpact();
    setState(() {
      for (final r in rows) {
        r.busy = false;
      }
      if (e.type == AppErrorType.network) {
        // Error honesto + Reintentar; la tarjeta NO se marca (FR-08).
        _retry = _PendingRetry(e.message, () => _enqueue(rows));
      }
    });
    if (e.type != AppErrorType.network) _toast(e.message, error: true);
  }

  // ── Revisión: confirmar / descartar (FR-05, FR-06, AC-06) ─────────────────

  Future<void> _confirmItems(List<_ReviewItem> items) async {
    if (items.isEmpty) return;
    setState(() {
      for (final i in items) {
        i.busy = true;
      }
      _retry = null;
    });
    try {
      await _api.confirmRetouchItems(items.map((i) => i.itemId).toList());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        for (final i in items) {
          i.busy = false;
          i.leaving = true; // AnimatedOpacity la saca; onEnd la remueve
          _handledItemIds.add(i.itemId);
          for (final r in _rows.where((r) => r.id == i.productId)) {
            r.done = true;
          }
        }
      });
      _toast(items.length == 1
          ? 'Foto aplicada a "${items.first.name}".'
          : '${items.length} fotos aplicadas.');
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        for (final i in items) {
          i.busy = false;
        }
        if (e.type == AppErrorType.network) {
          _retry = _PendingRetry(e.message, () => _confirmItems(items));
        }
      });
      if (e.type != AppErrorType.network) _toast(e.message, error: true);
    }
  }

  Future<void> _discardItem(_ReviewItem item) async {
    if (item.busy) return;
    HapticFeedback.selectionClick();
    setState(() => item.busy = true);
    try {
      await _api.discardRetouchItems([item.itemId]);
      if (!mounted) return;
      setState(() {
        item.busy = false;
        item.leaving = true;
        _handledItemIds.add(item.itemId);
        // La referencia vuelve a la lista de pendientes: su foto original
        // no cambió y sigue contando como sin retocar (AC-06).
        for (final r in _rows.where((r) => r.id == item.productId)) {
          r.queued = false;
        }
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => item.busy = false);
      _toast(e.message, error: true);
    }
  }

  Future<void> _applyAll() async {
    final items = _reviewables;
    if (items.isEmpty) return;
    HapticFeedback.lightImpact();
    final confirmed = await _confirmSheet(
      title: '¿Aplicar las fotos revisadas?',
      body: 'Se aplicarán ${items.length} fotos mejoradas. Las que usted '
          'ya descartó no se tocan.',
      confirmLabel: 'Aplicar ${items.length} fotos',
    );
    if (confirmed != true || !mounted) return;
    await _confirmItems(items);
  }

  // ── Cancelar lote (FR-15) ──────────────────────────────────────────────────

  Future<void> _cancelBatch() async {
    final id = (_batch?['id'] ?? '').toString();
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    try {
      await _api.cancelRetouchBatch(id);
      if (!mounted) return;
      setState(() {
        _batch = null;
        for (final r in _rows) {
          r.queued = false;
        }
      });
      _pollTimer?.cancel();
      _toast('Lote cancelado. Lo que ya estaba listo quedó para revisar.');
    } on AppError catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    }
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────

  Future<bool?> _confirmSheet({
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppUI.ink)),
            const SizedBox(height: AppUI.s8),
            Text(body, style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Ahora no'),
                ),
              ),
              const SizedBox(width: AppUI.s8),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size(0, 48)),
                  child: Text(confirmLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  static String _formatPrice(double price) {
    final s = price.round().toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Retocar fotos'),
      ),
      body: _allDone ? _allDoneView() : _content(),
    );
  }

  Widget _content() {
    final pending = _pendingRows;
    final review = _review.toList();
    return Column(
      children: [
        _header(),
        if (_retry != null) _retryBanner(),
        if (_batch != null) _progressBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // Los ítems listos aparecen ARRIBA a medida que llegan (D5:
              // revisar mientras el lote corre = espera útil).
              if (review.isNotEmpty) ...[
                _reviewHeader(),
                ...review.map(_animatedReviewCard),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: AppUI.s8),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Text('PENDIENTES', style: AppUI.sectionLabel),
                  ),
                ],
              ],
              ...pending.map(_pendingCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final idle = _idleRows;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_doneCount de ${_rows.length} retocadas',
              style: AppUI.bodyStrong),
          if (idle.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _retouchAll,
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: Text('Retocar todas (${idle.length})',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 48)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Error de red honesto: qué no se guardó + Reintentar (AC-05/FR-08).
  Widget _retryBanner() {
    final r = _retry!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.wifi_off_rounded, color: AppTheme.error, size: 22),
        const SizedBox(width: AppUI.s8),
        Expanded(child: Text(r.message, style: AppUI.bodyStrong)),
        TextButton(
          onPressed: r.action,
          child: const Text('Reintentar',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  /// Progreso del lote SIN ansiedad (D5): número de listas para revisar y
  /// una pausa por cupo de IA se cuenta en calma — jamás como error (AC-10).
  Widget _progressBanner() {
    final paused = _batchStatus == 'paused_error';
    final ready = (_batch?['ready_for_review'] as num?)?.toInt() ?? 0;
    final String text;
    if (paused) {
      text = 'La IA está ocupada un momento. Seguirá sola.';
    } else if (ready > 0) {
      text = ready == 1
          ? '1 lista para revisar · La IA sigue con las demás'
          : '$ready listas para revisar · La IA sigue con las demás';
    } else {
      text = 'La IA está retocando sus fotos. Puede cerrar la aplicación '
          'y volver cuando quiera.';
    }
    const accent = Color(0xFF7C3AED); // acento IA (mismo de los flujos IA)
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(AppUI.s12, AppUI.s12, AppUI.s8, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(paused ? Icons.hourglass_top_rounded : Icons.auto_awesome,
                color: accent, size: 22),
            const SizedBox(width: AppUI.s8),
            Expanded(child: Text(text, style: AppUI.bodyStrong)),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _cancelBatch,
              style: TextButton.styleFrom(foregroundColor: AppUI.inkSoft),
              child: const Text('Cancelar lote',
                  style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Revisión (antes/después) ───────────────────────────────────────────────

  Widget _reviewHeader() {
    final n = _reviewables.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        const Expanded(child: Text('POR REVISAR', style: AppUI.sectionLabel)),
        if (n > 1)
          TextButton.icon(
            onPressed: _applyAll,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text('Aplicar las $n'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
      ]),
    );
  }

  /// La tarjeta confirmada/descartada sale con animación y al terminar se
  /// remueve — sin Timers (seguro en pruebas y en dispose, patrón Spec 100).
  Widget _animatedReviewCard(_ReviewItem item) {
    return AnimatedOpacity(
      opacity: item.leaving ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      onEnd: () {
        if (item.leaving && mounted) {
          setState(() => _review.remove(item));
        }
      },
      child: _reviewCard(item),
    );
  }

  Widget _reviewCard(_ReviewItem item) {
    return RetouchReviewCard(
      name: item.name,
      originalUrl: item.originalUrl,
      candidateUrl: item.candidateUrl,
      busy: item.busy,
      onConfirm: () => _confirmItems([item]),
      onDiscard: () => _discardItem(item),
    );
  }

  // ── Tarjeta pendiente ──────────────────────────────────────────────────────

  Widget _pendingCard(_Row row) {
    return RetouchPendingCard(
      name: row.name,
      priceLabel: _formatPrice(row.price),
      photoUrl: row.photoUrl,
      busy: row.busy,
      queued: row.queued,
      onRetouch: () => _retouchOne(row),
    );
  }

  /// Estado vacío celebratorio (FR-06): no quedan fotos por retocar.
  Widget _allDoneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_rounded,
                size: 64, color: AppTheme.success),
            const SizedBox(height: AppUI.s16),
            const Text('¡Fotos impecables!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppUI.ink)),
            const SizedBox(height: 8),
            const Text(
              'Todas sus fotos ya están retocadas. Su catálogo y su POS '
              'se ven profesionales.',
              textAlign: TextAlign.center,
              style: AppUI.bodySoft,
            ),
            const SizedBox(height: AppUI.s24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 48)),
                child: const Text('Volver al inventario'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
