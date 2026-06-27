// Spec: specs/085-vender-por-voz/spec.md
//
// Hoja "Vender por voz": push-to-talk → entendiendo → PREVIEW editable → aplicar.
// Nada toca el carrito hasta "Agregar al pedido". Estética kit AppUI, copy USTED.

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
              ? 'Toque el micrófono cuando termine.'
              : 'Toque el micrófono y diga qué lleva.\nEjemplo: «dos Águila y una agua para la mesa 3».',
          textAlign: TextAlign.center,
          style: AppUI.bodySoft,
        ),
        const SizedBox(height: AppUI.s24),
        GestureDetector(
          key: const Key('voice_mic_button'),
          onTap: () {
            HapticFeedback.mediumImpact();
            if (recording) {
              c.stopAndProcess();
            } else {
              c.startRecording();
            }
          },
          child: Container(
            width: 104, height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.12),
              boxShadow: recording
                  ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4)]
                  : null,
            ),
            child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded,
                size: 48, color: recording ? Colors.white : AppTheme.primary),
          ),
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
          CircularProgressIndicator(),
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
