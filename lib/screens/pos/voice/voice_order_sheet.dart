// Spec: specs/085-vender-por-voz/spec.md
//
// Hoja "Vender por voz": push-to-talk → entendiendo → PREVIEW editable → aplicar.
// Nada toca el carrito hasta "Agregar al pedido". Estética kit AppUI, copy USTED.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/product.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_ui.dart';
import '../cart_controller.dart';
import 'product_resolver.dart';
import 'voice_command.dart';
import 'voice_order_controller.dart';

/// Abre la hoja de venta por voz sobre el [cart] activo. Devuelve un
/// [ApplyOutcome] si el tendero aplicó (para que el POS abra el cobro/vaciado),
/// o null si canceló.
Future<ApplyOutcome?> showVoiceOrderSheet(
  BuildContext context,
  CartController cart, {
  VoiceOrderController? controllerOverride,
}) {
  final controller = controllerOverride ?? VoiceOrderController(cart: cart);
  return showModalBottomSheet<ApplyOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VoiceOrderSheet(controller: controller),
  ).whenComplete(controller.dispose);
}

class _VoiceOrderSheet extends StatefulWidget {
  const _VoiceOrderSheet({required this.controller});
  final VoiceOrderController controller;

  @override
  State<_VoiceOrderSheet> createState() => _VoiceOrderSheetState();
}

class _VoiceOrderSheetState extends State<_VoiceOrderSheet> {
  VoiceOrderController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.fromLTRB(AppUI.s16, AppUI.s16, AppUI.s16,
              MediaQuery.viewInsetsOf(context).bottom + AppUI.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppUI.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppUI.s16),
              switch (c.phase) {
                VoicePhase.review => _buildReview(),
                VoicePhase.error => _buildError(),
                VoicePhase.uploading ||
                VoicePhase.resolving =>
                  _buildBusy(),
                _ => _buildRecorder(),
              },
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecorder() {
    final recording = c.phase == VoicePhase.recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(recording ? 'Le escucho…' : 'Vender por voz', style: AppUI.title),
        const SizedBox(height: AppUI.s8),
        Text(
          recording
              ? 'Hable normal. Cuando termine, sigo solo.\n(o toque para parar)'
              : 'Toque el micrófono y diga qué lleva.\nEjemplo: «dos Águila y una agua para la mesa 3».',
          textAlign: TextAlign.center,
          style: AppUI.bodySoft,
        ),
        const SizedBox(height: AppUI.s24),
        _ListeningOrb(
          key: const Key('voice_mic_button'),
          recording: recording,
          amplitude: c.amplitude,
          onTap: () {
            HapticFeedback.mediumImpact();
            if (recording) {
              c.stopAndProcess();
            } else {
              c.startRecording();
            }
          },
        ),
        const SizedBox(height: AppUI.s24),
      ],
    );
  }

  Widget _buildBusy() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppUI.s24),
      child: Column(
        children: [
          _ThinkingDots(),
          SizedBox(height: AppUI.s16),
          Text('Entendiendo lo que dijo…', style: AppUI.bodySoft),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mic_off_rounded, size: 40, color: AppUI.inkSoft),
        const SizedBox(height: AppUI.s12),
        Text(c.error ?? 'No se pudo procesar.',
            textAlign: TextAlign.center, style: AppUI.bodySoft),
        const SizedBox(height: AppUI.s24),
        AppButton(
          label: 'Hablar otra vez',
          icon: Icons.mic_rounded,
          onPressed: c.reset,
        ),
        const SizedBox(height: AppUI.s8),
        AppButton(
          label: 'Cerrar',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildReview() {
    final preview = c.preview;
    final applicable = preview.lines
        .where((l) => l.status == ResolveStatus.matched && !l.priceMissing)
        .length;
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Revise el pedido', style: AppUI.title),
            const SizedBox(height: AppUI.s12),
            if (preview.target != null) _targetBanner(preview),
            if (preview.clarifyPrompt != null) ...[
              _hintCard(preview.clarifyPrompt!),
              const SizedBox(height: AppUI.s8),
            ],
            ...preview.lines.map(_lineCard),
            if (preview.hasVaciar) _flagCard(
                Icons.delete_outline_rounded, 'Pidió VACIAR la orden — se confirmará aparte.'),
            if (preview.hasCobrar) _flagCard(
                Icons.point_of_sale_rounded, 'Pidió COBRAR — abrirá el cobro al confirmar.'),
            if (c.error != null) ...[
              const SizedBox(height: AppUI.s8),
              _hintCard(c.error!),
            ],
            const SizedBox(height: AppUI.s8),
            const Text('Diga p. ej.: «quite la gaseosa» o «que el agua sean tres».',
                style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s16),
            // Acción primaria: aplicar al pedido.
            AppButton(
              label: 'Agregar al pedido',
              icon: Icons.check_rounded,
              onPressed: applicable == 0 && !preview.hasCobrar && !preview.hasVaciar
                  ? null
                  : _apply,
            ),
            const SizedBox(height: AppUI.s8),
            // Corrección por voz SOBRE esta preview (mergea, no reemplaza).
            AppButton(
              key: const Key('voice_correct_button'),
              label: 'Corregir hablando',
              icon: Icons.mic_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () {
                HapticFeedback.mediumImpact();
                c.startCorrection();
              },
            ),
            const SizedBox(height: AppUI.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: c.reset,
                  child: const Text('Empezar de nuevo',
                      style: TextStyle(fontSize: 14)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    // Confirmaciones extra para acciones destructivas/finales.
    if (c.preview.hasVaciar) {
      final ok = await _confirm('¿Vaciar toda la orden?', 'Sí, vaciar');
      if (ok != true) return;
    }
    final outcome = c.applyConfirmed();
    if (mounted) Navigator.of(context).pop(outcome);
  }

  Future<bool?> _confirm(String title, String okLabel) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('No')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(okLabel)),
          ],
        ),
      );

  Widget _targetBanner(PreviewModel preview) {
    final t = preview.target!;
    final label = switch (t.type) {
      VoiceTargetType.mesa => 'Para: Mesa ${t.mesa}',
      VoiceTargetType.cliente => 'Para: ${t.cliente}',
      VoiceTargetType.mostrador => 'Para: Mostrador',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s12),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppUI.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_rounded, color: AppTheme.primary, size: 20),
          const SizedBox(width: AppUI.s8),
          Expanded(child: Text(label, style: AppUI.bodyStrong)),
        ],
      ),
    );
  }

  Widget _hintCard(String text) => Container(
        padding: const EdgeInsets.all(AppUI.s12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(AppUI.radius),
        ),
        child: Text(text, style: AppUI.bodySoft),
      );

  Widget _flagCard(IconData icon, String text) => Container(
        margin: const EdgeInsets.only(top: AppUI.s8),
        padding: const EdgeInsets.all(AppUI.s12),
        decoration: BoxDecoration(
          color: AppUI.pageBg,
          borderRadius: BorderRadius.circular(AppUI.radius),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: AppUI.inkSoft),
          const SizedBox(width: AppUI.s8),
          Expanded(child: Text(text, style: AppUI.bodySoft)),
        ]),
      );

  Widget _lineCard(PreviewLine line) {
    final actionVerb = switch (line.action) {
      VoiceAction.quitar => 'Quitar',
      VoiceAction.fijarCantidad => 'Dejar en',
      _ => 'Agregar',
    };
    // No encontrado.
    if (line.status == ResolveStatus.notFound) {
      return _wrap(Row(children: [
        const Icon(Icons.help_outline_rounded, color: Colors.redAccent, size: 20),
        const SizedBox(width: AppUI.s8),
        Expanded(
          child: Text('No encontré «${line.spokenName}»',
              style: AppUI.bodySoft),
        ),
        TextButton(onPressed: () => c.removeLine(line), child: const Text('Quitar')),
      ]));
    }
    // Ambiguo → chooser.
    if (line.status == ResolveStatus.ambiguous) {
      return _wrap(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Cuál «${line.spokenName}»?', style: AppUI.bodyStrong),
          const SizedBox(height: AppUI.s8),
          ...line.candidates.map((cand) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(cand.name),
                trailing: Text('\$${cand.price.round()}'),
                onTap: () => c.chooseCandidate(line, cand),
              )),
          TextButton(onPressed: () => c.removeLine(line), child: const Text('Quitar esta')),
        ],
      ));
    }
    // Resuelto.
    final Product prod = line.product!;
    return _wrap(Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$actionVerb: ${prod.name}', style: AppUI.bodyStrong),
              if (line.priceMissing)
                const Text('Falta el precio',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            ],
          ),
        ),
        _stepper(line),
      ],
    ));
  }

  Widget _stepper(PreviewLine line) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: line.quantity <= 0
              ? null
              : () => c.setLineQuantity(line, line.quantity - 1),
        ),
        Text('${line.quantity}', style: AppUI.bodyStrong),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
          onPressed: () => c.setLineQuantity(line, line.quantity + 1),
        ),
      ],
    );
  }

  Widget _wrap(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: AppUI.s8),
        padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: AppUI.s8),
        decoration: BoxDecoration(
          border: Border.all(color: AppUI.hairline),
          borderRadius: BorderRadius.circular(AppUI.radius),
        ),
        child: child,
      );
}

/// Botón-micrófono VIVO. En reposo respira suave; grabando, unos anillos
/// concéntricos crecen con la amplitud REAL de la voz ([amplitude] 0..1), para
/// que el tendero vea que el sistema lo está escuchando. Un solo
/// AnimationController (barato para gama baja); la amplitud se suaviza entre
/// lecturas para que no titile.
class _ListeningOrb extends StatefulWidget {
  const _ListeningOrb({
    super.key,
    required this.recording,
    required this.amplitude,
    required this.onTap,
  });

  final bool recording;
  final double amplitude; // 0..1
  final VoidCallback onTap;

  @override
  State<_ListeningOrb> createState() => _ListeningOrbState();
}

class _ListeningOrbState extends State<_ListeningOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  double _smooth = 0.0; // amplitud suavizada

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primary = AppTheme.primary;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 168,
        height: 168,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            // Suaviza la amplitud hacia el último valor leído (evita saltos a
            // ~6 fps que da el stream de amplitud).
            _smooth += (widget.amplitude - _smooth) * 0.25;
            // Respiración base con una onda seno; en reposo mantiene el orbe vivo.
            final breath = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
            final energy = widget.recording ? _smooth : 0.0;

            // Anillos externos: escalan con respiración + energía de la voz.
            final outer = 96.0 + breath * 10 + energy * 64;
            final mid = 96.0 + energy * 34;

            return Stack(
              alignment: Alignment.center,
              children: [
                _ring(outer, primary.withValues(alpha: 0.10 + energy * 0.10)),
                _ring(mid, primary.withValues(alpha: 0.16)),
                // Núcleo tocable.
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.recording
                        ? primary
                        : primary.withValues(alpha: 0.12),
                    boxShadow: widget.recording
                        ? [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.25 + energy * 0.25),
                              blurRadius: 20 + energy * 24,
                              spreadRadius: 2 + energy * 6,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    widget.recording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 44,
                    color: widget.recording ? Colors.white : primary,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        width: size.clamp(96.0, 168.0),
        height: size.clamp(96.0, 168.0),
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

/// Tres puntos que laten en secuencia mientras la IA "entiende" el audio —
/// reemplaza al spinner pelado para que la espera se sienta activa.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Cada punto desfasado 1/3 de ciclo.
            final phase = (_c.value + i / 3) % 1.0;
            final wave = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withValues(alpha: 0.35 + wave * 0.55),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
